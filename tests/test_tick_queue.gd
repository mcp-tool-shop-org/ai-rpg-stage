## test_tick_queue.gd — presentation happens one thing at a time, in order.
##
## The property is easy to state and easy to lose: the sim resolves a whole tick at
## once, and a renderer that reacts to all of it at once plays a door opening, a guard
## turning and a refusal being spoken simultaneously. The queue's only job is to stop
## that, and the only way to prove it is with a presenter that takes TIME — a
## presenter that returned immediately would satisfy a broken queue too.
##
## ⚠ TWO GDSCRIPT TRAPS, both hit while writing this file, both recorded because they
## make a test read as passing when it measured nothing:
##
##   1. **Lambdas capture locals BY VALUE.** `var n := 0` then `n += 1` inside a
##      lambda increments the lambda's own copy; the outer `n` stays 0. Arrays and
##      Dictionaries survive because the mutation goes through the shared object, not
##      through the name. So every counter here is a one-element Array. The first
##      draft used a plain int and the overlap counter read 0 — which an assertion of
##      `<= 1` would have accepted as proof of serialisation. `== 1` caught it.
##
##   2. **A signal is not a method.** `q.call("drained")` fails; the signal is reached
##      as `q.drained`. Which is why the queue is held in an UNTYPED variable here:
##      dynamic dispatch reaches signals and methods alike, and `q.drain()` reads like
##      what it is instead of `q.call("drain")`.
extends RefCounted

const TickQueue := preload("res://client/tick_queue.gd")


func run_async(t: RefCounted) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		t.check(false, "a SceneTree is available", "the queue's waiting needs a timer")
		return

	await _drains_in_order(t)
	await _serialises_slow_presentation(t, tree)
	await _reentrant_drain_is_refused(t, tree)
	await _empty_drain_still_signals(t)


func _drains_in_order(t: RefCounted) -> void:
	var q = TickQueue.new()
	var seen: Array[String] = []
	q.presenter = func(e: Dictionary) -> Variant:
		seen.append(String(e.get("id", "")))
		return null

	q.enqueue([{"id": "a"}, {"id": "b"}, {"id": "c"}])
	t.equals(q.pending_count(), 3, "three events queued")
	await q.drain()

	t.equals(seen, ["a", "b", "c"] as Array[String], "events present in the order the sim resolved them")
	t.equals(q.pending_count(), 0, "the queue is empty afterwards")
	t.equals(q.presented_count(), 3, "and counts what it presented")


func _serialises_slow_presentation(t: RefCounted, tree: SceneTree) -> void:
	# The load-bearing case. Each presentation waits on a real timer, so if the queue
	# started the next one early the overlap is observable.
	var q = TickQueue.new()
	var in_flight := [0]      # boxed: see trap 1
	var max_in_flight := [0]
	var order: Array[String] = []

	q.presenter = func(e: Dictionary) -> Variant:
		in_flight[0] += 1
		max_in_flight[0] = max(max_in_flight[0], in_flight[0])
		order.append(String(e.get("id", "")))
		var timer := tree.create_timer(0.05)
		# Decrement when the wait ENDS, so the counter reflects real overlap rather
		# than call-and-return.
		timer.timeout.connect(func() -> void: in_flight[0] -= 1)
		return timer.timeout

	q.enqueue([{"id": "one"}, {"id": "two"}, {"id": "three"}])
	await q.drain()

	t.equals(max_in_flight[0], 1, "never more than one presentation in flight at a time")
	t.equals(order, ["one", "two", "three"] as Array[String], "and still in order")
	t.equals(q.presented_count(), 3, "all three presented")


func _reentrant_drain_is_refused(t: RefCounted, tree: SceneTree) -> void:
	# Two concurrent drains would interleave presentation — the one thing this class
	# exists to prevent — so a second call must return rather than start a second loop.
	var q = TickQueue.new()
	var presented := [0]
	q.presenter = func(_e: Dictionary) -> Variant:
		presented[0] += 1
		return tree.create_timer(0.04).timeout

	q.enqueue([{"id": "x"}, {"id": "y"}])
	# Start one drain WITHOUT awaiting it, then call again while it is mid-flight.
	q.drain()
	t.is_true(q.is_draining(), "the first drain is running")
	await q.drain() # must return immediately rather than start a second loop
	await q.drained

	t.equals(presented[0], 2, "each event presented exactly once despite two drain calls")
	t.equals(q.presented_count(), 2, "and counted once each")
	t.is_false(q.is_draining(), "the drain finished")


func _empty_drain_still_signals(t: RefCounted) -> void:
	# A caller that awaits `drain()` on an empty queue must not hang. That is the
	# ordinary case for a tick which resolved nothing observable, and it happens often.
	var q = TickQueue.new()
	var fired := [false]
	q.drained.connect(func() -> void: fired[0] = true)
	await q.drain()
	t.is_true(fired[0], "draining an empty queue still signals completion")
	t.equals(q.presented_count(), 0, "having presented nothing")

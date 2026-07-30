## tick_queue.gd — present simulation events one at a time, in order.
##
## The simulation resolves a whole tick at once. A renderer that reacted to all of it
## at once would play a door opening, a guard turning, and a refusal being spoken
## simultaneously — technically correct and unreadable. godot-open-rpg's turn queue
## is the shape: hold the events, hand them to a presenter ONE at a time, and let
## each one take as long as it needs before the next begins.
##
## The queue owns ORDER and never CONTENT. It cannot skip an event, cannot reorder
## one, and cannot decide that something did not happen — the sim already decided all
## of that. Its single job is to stop presentation from overlapping.
##
## The presenter is a Callable: `func(event: Dictionary) -> Variant`. Whatever it
## returns says how long to wait:
##
##   null / anything else   continue immediately
##   a Signal               await it (a tween's `finished`, an animation's)
##   a Tween                await its `finished`
##
## That indirection is what makes this testable headlessly: a presenter that returns
## null drains the whole queue instantly and the ORDER can still be asserted, with no
## rendering and no waiting.
extends RefCounted

## Every queued event has been presented.
signal drained

## Presentation of one event finished. Carries the event and its 0-based index within
## the whole run, so a test can assert order without instrumenting the presenter.
signal presented(event: Dictionary, index: int)

var presenter: Callable = Callable()

var _pending: Array[Dictionary] = []
var _draining := false
var _presented_count := 0
## Events queued while a drain was already running. Recorded because a tick arriving
## mid-presentation is normal, and silently merging it into the current batch would
## make "how many ticks did we present" unanswerable.
var _interleaved := 0


## Queue a tick's events. Safe to call while a drain is in flight.
func enqueue(events: Array) -> void:
	if _draining:
		_interleaved += 1
	for e: Variant in events:
		if e is Dictionary:
			_pending.append(e as Dictionary)


## Drain the queue, awaiting whatever the presenter asks to wait for.
##
## Re-entrant calls return immediately rather than starting a second drain — two
## concurrent drains would interleave presentation, which is the one thing this class
## exists to prevent.
func drain() -> void:
	if _draining:
		return
	_draining = true

	while not _pending.is_empty():
		var event: Dictionary = _pending.pop_front()
		var wait: Variant = null
		if presenter.is_valid():
			wait = presenter.call(event)

		if wait is Signal:
			await (wait as Signal)
		elif wait is Tween:
			await (wait as Tween).finished

		presented.emit(event, _presented_count)
		_presented_count += 1

	_draining = false
	drained.emit()


func pending_count() -> int:
	return _pending.size()


func presented_count() -> int:
	return _presented_count


func is_draining() -> bool:
	return _draining


## How many times a tick arrived while a drain was already running.
func interleaved_count() -> int:
	return _interleaved

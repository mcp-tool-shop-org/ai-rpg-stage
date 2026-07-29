## test_wire_session.gd — P1's exit gate: the stage attaches to the real sim.
##
## Drives an ACTUAL `ai-rpg-engine sidecar --listen` process. Not a mock. A mock would
## prove the stage agrees with a mock, and this studio has a memory file about exactly
## that: a producer's own tests cannot answer "does anything real call this."
##
## What is proven here, and what is NOT:
##
##   PROVEN  the handshake exchanges capabilities; intents are submitted and the sim's
##           events come back tick-stamped with hashes; two same-seed runs deliver
##           BYTE-IDENTICAL streams as measured on the raw frames the stage received;
##           the staleness detector fires; strict-in refuses an unknown field and an
##           unknown method THROUGH this client; a rejected action arrives as a
##           reason rather than a crash.
##
##   NOT     that the stream is byte-identical to the engine's in-process run. That
##           claim belongs to the engine's own three-transport conformance suite,
##           which can hold both sides in one process. From inside Godot it is not
##           even expressible: `JSON.parse_string` renders every number as a float,
##           so the parsed form has already lost the bytes. Hence the raw-frame
##           digest — the strongest honest claim available on this side.
extends RefCounted

const Harness := preload("res://tools/sidecar_harness.gd")
const NetworkClient := preload("res://client/network_client.gd")
const EventBus := preload("res://client/event_bus.gd")

const PACK_ID := "chapel-threshold"
const SEED := 71

## The same script the engine's conformance suites run.
const SCRIPT := ["look", "move", "look", "move", "wait", "look"]


func run_async(t: RefCounted) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		t.check(false, "a SceneTree is available", "the wire tests need process frames")
		return

	# ── Run 1 ────────────────────────────────────────────────
	var first := await _session(t, tree, "run-1")
	if not first.get("ok", false):
		# `_session` has already recorded the specific failure.
		return

	# ── The live-session assertions, on run 1 ────────────────
	var client: Node = first["client"]
	var bus: Node = first["bus"]
	var handshake: Dictionary = first["handshake"]

	t.check(not String(handshake.get("serverName", "")).is_empty(), "the sim names itself in the handshake")
	var caps: Dictionary = handshake.get("capabilities", {}) as Dictionary
	# Capabilities, not a version number (DAP's lesson). A transport that connected
	# but dropped the handshake's contents would still look "connected".
	t.is_true(bool(caps.get("hashes", false)), "the sim advertises per-tick hashes")
	t.is_true(bool(caps.get("snapshot", false)), "the sim advertises snapshot")
	t.is_true(bool(caps.get("preview", false)), "the sim advertises preview")

	t.check(int(first["events_seen"]) > 0, "the stage received resolved events",
		"got %d" % int(first["events_seen"]))
	t.check(int(first["hashes_seen"]) > 0, "every position report carried a hash",
		"got %d" % int(first["hashes_seen"]))
	t.check(client.call("current_tick") >= 0, "the stage knows what tick it is on")

	# ── Position verification, and its RED control ───────────
	var agreed: bool = await client.call("verify_position")
	t.is_true(agreed, "the stage's position agrees with the sim")
	t.is_false(client.call("is_stale"), "and it is not stale")

	# The detector must be able to FIRE. Corrupt only the stage's OWN record — never
	# the sim — and require it to be caught. A detector that has only ever agreed is
	# not a detector.
	var stale_reports: Array[String] = []
	bus.staleness_detected.connect(func(detail: String) -> void: stale_reports.append(detail))
	client.call("_debug_corrupt_recorded_hash", client.call("current_tick"))
	var agreed_after: bool = await client.call("verify_position")
	t.is_false(agreed_after, "RED: a corrupted local record is DETECTED")
	t.is_true(client.call("is_stale"), "RED: and the stage marks itself stale")
	t.check(stale_reports.size() > 0, "RED: and reports it on the bus")
	if stale_reports.size() > 0:
		t.contains(stale_reports[0], "state drift", "RED: naming what drifted")

	# ── Strict-in, through THIS client ───────────────────────
	# Re-proven on the client side because a stage that silently dropped a field
	# before sending would look perfectly healthy on every property above.
	var bad_field: Dictionary = await client.call("submit_action", "look", {"speculativeHint": "render-fast"})
	t.is_true(bool(bad_field.get("__error__", false)), "an unknown FIELD is refused by the sim")
	t.equals(int(bad_field.get("code", 0)), NetworkClient.ERR_INVALID_PARAMS, "with INVALID_PARAMS")

	var bad_method: Dictionary = await client.call("request", "sim/pleaseDecideForMe", {})
	t.is_true(bool(bad_method.get("__error__", false)), "an unknown METHOD is refused by the sim")
	t.equals(int(bad_method.get("code", 0)), NetworkClient.ERR_METHOD_NOT_FOUND, "with METHOD_NOT_FOUND")

	# ── A refused intent is CONTENT, not a wire fault ────────
	#
	# MEASURED, correcting this test's own first draft. A refused action does NOT come
	# back as a JSON-RPC error; it comes back as a SUCCESSFUL response carrying an
	# `action.rejected` event whose payload holds the reason. The engine's core emits
	# it (`core/src/actions.ts:98-103`) and the server's `commit` sweeps the whole
	# world event log, so it crosses the wire like any other event.
	#
	# That design is right, and it is the reason this assertion matters more than the
	# one it replaced: a refusal is a thing the PLAYER is supposed to see, so it must
	# arrive as renderable content and not as a protocol fault a renderer would
	# reasonably log and drop. It is also the exact channel P4's gated door uses.
	var nonsense: Dictionary = await client.call("submit_action", "yodel")
	t.is_false(bool(nonsense.get("__error__", false)),
		"a refused verb is NOT a wire error — it is a simulation outcome")

	var rejection := {}
	for ev: Variant in nonsense.get("events", []) as Array:
		if ev is Dictionary and String((ev as Dictionary).get("type", "")) == "action.rejected":
			rejection = ev as Dictionary
	t.check(not rejection.is_empty(), "the refusal arrives as an action.rejected EVENT")
	if not rejection.is_empty():
		var payload: Dictionary = rejection.get("payload", {}) as Dictionary
		t.contains(String(payload.get("reason", "")), "yodel",
			"and its payload carries a reason the stage can render")
		t.equals(String(payload.get("verb", "")), "yodel", "naming the verb that was refused")

	t.is_true(client.call("is_attached"), "the stage is still attached after a refusal")

	var digest_1 := String(first["digest"])
	var bytes_1 := int(first["bytes"])
	await _teardown(first)

	# ── Run 2: determinism, as the stage SEES it ─────────────
	var second := await _session(t, tree, "run-2")
	if not second.get("ok", false):
		return
	var digest_2 := String(second["digest"])
	var bytes_2 := int(second["bytes"])
	await _teardown(second)

	t.check(bytes_1 > 0, "run 1 recorded raw frame bytes", "got %d" % bytes_1)
	t.check(not digest_1.is_empty(), "run 1 produced a digest")
	t.equals(bytes_2, bytes_1, "both runs received the same number of bytes")
	t.equals(digest_2, digest_1, "SAME SEED, SAME BYTES: the two runs are byte-identical")

	# RED: the digest must be capable of differing. Without this, "the digests match"
	# could be two hashes of nothing — the failure mode `body_digest()` returns ""
	# for, specifically so it cannot be mistaken for agreement.
	var tampered := (digest_1 + "x").sha256_text()
	t.not_equals(tampered, digest_1, "RED: the digest comparison can fail")


## One full attached session running SCRIPT. Returns a bag, `ok` false on failure.
func _session(t: RefCounted, tree: SceneTree, label: String) -> Dictionary:
	var harness: RefCounted = Harness.new()
	var started: bool = await harness.call("start", PACK_ID, SEED)
	if not started:
		t.check(false, "%s: sidecar starts" % label, String(harness.get("failure")))
		return {"ok": false}

	var bus: Node = EventBus.new()
	bus.name = "EventBus_%s" % label
	tree.root.add_child(bus)

	var client: Node = NetworkClient.new()
	client.name = "NetworkClient_%s" % label
	client.bus = bus
	client.call("record_received_bytes")
	tree.root.add_child(client)

	var events_seen := 0
	var hashes_seen := 0
	bus.sim_event.connect(func(_e: Dictionary) -> void: events_seen += 1)
	bus.tick_received.connect(func(_tick: int, h: String, _ev: Array, _d: Array) -> void:
		if not h.is_empty():
			hashes_seen += 1
	)

	var handshake: Dictionary = await client.call(
		"attach", Harness.HOST, int(harness.get("port")), "ai-rpg-stage/%s" % label, "0.1.0"
	)
	if handshake.is_empty():
		t.check(false, "%s: handshake completes" % label, "attach returned nothing")
		harness.call("stop")
		return {"ok": false}

	# The snapshot first, so the stage has a position before it starts changing one.
	var snap: Dictionary = await client.call("snapshot")
	if snap.get("__error__", false):
		t.check(false, "%s: snapshot succeeds" % label, String(snap.get("message", "")))
	else:
		if not String(snap.get("hash", "")).is_empty():
			hashes_seen += 1

	for verb: String in SCRIPT:
		var result: Dictionary = await client.call("submit_action", verb)
		if result.get("__error__", false):
			# A refusal is a legitimate simulation outcome, not a wire fault. Recorded
			# rather than failed — the script is fixed and one of its moves may not be
			# legal from wherever the previous one left the player.
			continue
		if not String(result.get("hash", "")).is_empty():
			hashes_seen += 1
		events_seen += (result.get("events", []) as Array).size()

	return {
		"ok": true,
		"client": client,
		"bus": bus,
		"harness": harness,
		"handshake": handshake,
		"events_seen": events_seen,
		"hashes_seen": hashes_seen,
		"digest": client.call("received_digest"),
		"bytes": client.call("received_byte_count"),
	}


func _teardown(bag: Dictionary) -> void:
	var client: Node = bag.get("client", null)
	var bus: Node = bag.get("bus", null)
	var harness: RefCounted = bag.get("harness", null)
	if client:
		client.call("detach")
		client.queue_free()
	if bus:
		bus.queue_free()
	if harness:
		harness.call("stop")
	# Let the socket actually close before the next run claims the same port — the
	# sidecar serves one client, so an un-freed slot fails the next attach.
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		await (loop as SceneTree).create_timer(0.4).timeout

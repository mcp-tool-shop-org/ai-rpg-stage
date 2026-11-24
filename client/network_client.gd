## network_client.gd — the stage's only connection to the truth.
##
## Attaches to a running `ai-rpg-engine sidecar --listen <port>` over TCP and speaks
## the JSON-RPC contract: intents in, tick-stamped events out. It submits and it
## listens. It does not decide, it does not advance, and when it disagrees with the
## simulation it says so and stops trusting itself.
##
## THE GODOT TRAP, first, because it costs everyone an hour once:
## `StreamPeerTCP.poll()` must be called explicitly every frame. Without it the peer
## sits in STATUS_CONNECTING forever, `get_status()` never advances, and the symptom
## is a connection that "silently fails" against a server that is plainly listening.
## `_process` calls `poll()` before anything else, on every frame, unconditionally.
##
## WHAT IT MEANS TO VERIFY A HASH HERE:
## The stage negotiates `capabilities.canonicalHashes` (digest spec v2) during
## `initialize`, maintains `mirrored_state` from the authoritative snapshot and every
## incremental delta, and recomputes `StateDigest.canonical_state_hash` after every play
## submit (`submitAction` / `advance`) using the shared integer-scaled pre-image format.
##
## If the mirror digest disagrees with the engine's `canonicalHash` for that tick, the
## client logs the mismatch with the first differing pre-image byte offset, requests a
## full authoritative `snapshot`, replaces its mirror from that snapshot, and immediately
## verifies the fresh mirror's canonical digest. Consecutive resyncs are bounded to
## `MAX_CONSECUTIVE_RESYNCS` (3): past the cap (or if a fresh snapshot still diverges),
## play stops with a visible error.
extends Node

const Framing := preload("res://client/framing.gd")
const StateDigest := preload("res://client/state_digest.gd")

const SUPPORTED_DIGEST_SPEC_VERSION := StateDigest.DIGEST_SPEC_VERSION
const MAX_CONSECUTIVE_RESYNCS := 3
const ERR_SESSION_HALTED := -32099
const ERR_NOT_SYNCED := -32098

# ── Protocol constants, mirrored from the engine's protocol.ts ──
const METHOD_INITIALIZE := "initialize"
const METHOD_SNAPSHOT := "snapshot"
const METHOD_SUBMIT_ACTION := "submitAction"
const METHOD_ADVANCE := "advance"
const METHOD_PREVIEW := "preview"
const METHOD_REPLAY := "replay"
const METHOD_SHUTDOWN := "shutdown"

const NOTIFY_TICK := "sim/tick"
const NOTIFY_CLOSING := "sim/closing"

## JSON-RPC reserved codes plus this protocol's own, from protocol.ts ERROR_CODES.
const ERR_METHOD_NOT_FOUND := -32601
const ERR_INVALID_PARAMS := -32602
const ERR_NOT_INITIALIZED := -32000
const ERR_ACTION_REJECTED := -32003

## Emitted after every poll, so `request()` can wait without a busy loop.
signal polled

var bus: Node = null

var _peer := StreamPeerTCP.new()
var _framing: RefCounted = Framing.new()
var _next_id := 1
var _responses: Dictionary = {}
var _handshake: Dictionary = {}
var _connected := false
var _closing_reason := ""

## Position, canonical mirror, and bounded resync state.
var _tick := -1
var _hash_by_tick: Dictionary = {}
var _canonical_by_tick: Dictionary = {}
var _mirror: Variant = {}
var _has_baseline := false
var _applied_snapshot_seq := 0
var _tick_deltas_applied := 0
var _applied_via_rpc_queue: Array[Dictionary] = []
var _stale := false
var _consecutive_resyncs := 0
var _total_resyncs := 0
var _mismatch_log: Array[String] = []
var _halted := false
var _halt_reason := ""
var _last_attach_error := ""

## Negative tests exercising the 4-resync cap set this true so CI's failure-marker
## check distinguishes an intentional test halt from an unexpected live halt.
var suppress_ci_halt_marker := false

## Request timeout. Wall-clock, and deliberately so: it bounds a NETWORK failure,
## never a simulation outcome, so it cannot affect what the sim decides or the order
## it decides things in.
const REQUEST_TIMEOUT_MS := 20000


func _ready() -> void:
	# Poll every frame even before a connection exists — `poll()` is what drives the
	# CONNECTING → CONNECTED transition in the first place.
	set_process(true)


func _process(_delta: float) -> void:
	# FIRST, unconditionally. See the trap note at the top of this file.
	_peer.poll()

	var status := _peer.get_status()
	if status == StreamPeerTCP.STATUS_ERROR:
		_drop("socket error")
		polled.emit()
		return
	if status != StreamPeerTCP.STATUS_CONNECTED:
		polled.emit()
		return

	var available := _peer.get_available_bytes()
	if available > 0:
		var got: Array = _peer.get_partial_data(available)
		# get_partial_data returns [error, PackedByteArray]. Reading [1] without
		# checking [0] is how a read error becomes an empty message nobody noticed.
		if (got[0] as int) != OK:
			_report("read error %d" % (got[0] as int))
		else:
			for msg: Dictionary in _framing.push(got[1] as PackedByteArray):
				_dispatch(msg)

	for e: String in _framing.errors():
		_report("framing %s" % e)

	polled.emit()


# ── Connecting ────────────────────────────────────────────────

## Connect and complete the handshake. Returns the server's `initialize` result, or
## an empty Dictionary on failure (with the reason already on the bus).
func attach(host: String, port: int, client_name := "ai-rpg-stage", client_version := "0.1.0") -> Dictionary:
	_last_attach_error = ""
	_closing_reason = ""
	_handshake = {}
	_connected = false
	_tick = -1
	_hash_by_tick.clear()
	_canonical_by_tick.clear()
	_mirror = {}
	_has_baseline = false
	_applied_snapshot_seq = 0
	_tick_deltas_applied = 0
	_applied_via_rpc_queue.clear()
	_stale = false
	_consecutive_resyncs = 0
	_halted = false
	_halt_reason = ""
	var err := _peer.connect_to_host(host, port)
	if err != OK:
		_last_attach_error = "connect_to_host(%s:%d) failed: %d" % [host, port, err]
		_report(_last_attach_error)
		return {}

	# Small frames, sent immediately. Nagle would hold an intent back waiting for
	# company, which for an interactive client is latency for nothing.
	_peer.set_no_delay(true)

	var waited := 0
	while _peer.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		await polled
		waited += 1
		if waited > 6000:
			_last_attach_error = "timed out connecting to %s:%d" % [host, port]
			_report(_last_attach_error)
			return {}

	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		# A refusal arrives as a `sim/closing` notification and then a close, so the
		# reason may already be here.
		_last_attach_error = "could not connect to %s:%d%s" % [host, port,
			"" if _closing_reason.is_empty() else " — " + _closing_reason]
		_report(_last_attach_error)
		return {}

	var result: Dictionary = await request(METHOD_INITIALIZE, {
		"clientName": client_name,
		"clientVersion": client_version,
		# Request canonicalHashes (digest_spec_version == 2) so the stage can recompute
		# and verify every tick's digest against its delta-maintained mirror.
		"capabilities": {
			"notifications": true,
			"hashes": true,
			"canonicalHashes": true,
			"audio": true,
		},
	})
	if result.get("__error__", false):
		_last_attach_error = "initialize failed: %s" % result.get("message", "unknown")
		_report(_last_attach_error)
		return {}

	var version_check := _validate_handshake_digest_version(result)
	if not version_check.is_empty():
		_last_attach_error = version_check
		_report("load error: %s" % _last_attach_error)
		_peer.disconnect_from_host()
		_connected = false
		return {}

	_handshake = result
	_connected = true
	_tick = int(result.get("tick", -1))
	if bus:
		bus.connected.emit(
			String(result.get("serverName", "")),
			String(result.get("engineVersion", "")),
			result.get("capabilities", {}) as Dictionary,
		)
	return result


func _validate_handshake_digest_version(result: Dictionary) -> String:
	if not result.has("digest_spec_version"):
		return "unsupported digest_spec_version (missing; stage requires %d)" % SUPPORTED_DIGEST_SPEC_VERSION
	var raw_ver: Variant = result.get("digest_spec_version")
	var valid_int := false
	var ver_num := -1
	if typeof(raw_ver) == TYPE_INT:
		valid_int = true
		ver_num = int(raw_ver)
	elif typeof(raw_ver) == TYPE_FLOAT:
		var vf := float(raw_ver)
		if is_finite(vf) and vf == floor(vf):
			valid_int = true
			ver_num = int(vf)
	if not valid_int or ver_num != SUPPORTED_DIGEST_SPEC_VERSION:
		return "unsupported digest_spec_version %s (stage requires %d)" % [str(raw_ver), SUPPORTED_DIGEST_SPEC_VERSION]
	var caps := result.get("capabilities", {}) as Dictionary
	if not bool(caps.get("canonicalHashes", false)):
		return "server refused capabilities.canonicalHashes for digest_spec_version %d" % SUPPORTED_DIGEST_SPEC_VERSION
	return ""


func is_attached() -> bool:
	return _connected and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED


func capabilities() -> Dictionary:
	return (_handshake.get("capabilities", {}) as Dictionary).duplicate()


func detach() -> void:
	if _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_write({"jsonrpc": "2.0", "id": _alloc_id(), "method": METHOD_SHUTDOWN, "params": {}})
	_peer.disconnect_from_host()
	_connected = false
	_has_baseline = false


# ── Requests ──────────────────────────────────────────────────

## Send a request and await its response.
##
## On a protocol error the returned Dictionary carries `__error__: true` plus `code`
## and `message`. An error is RETURNED rather than thrown because most of them are
## ordinary game outcomes — ACTION_REJECTED is the sim refusing an intent, which is
## the system working, and a refusal at a gated door is a thing the player is
## supposed to see.
func request(method: String, params: Dictionary = {}) -> Dictionary:
	var id := _alloc_id()
	_write({"jsonrpc": "2.0", "id": id, "method": method, "params": params})

	var started := Time.get_ticks_msec()
	while not _responses.has(id):
		if not _connected and method != METHOD_INITIALIZE:
			return _error(-1, "not attached")
		if _peer.get_status() == StreamPeerTCP.STATUS_NONE:
			return _error(-1, "connection closed%s" % ("" if _closing_reason.is_empty() else ": " + _closing_reason))
		if Time.get_ticks_msec() - started > REQUEST_TIMEOUT_MS:
			return _error(-1, "timeout on %s" % method)
		await polled

	var entry: Dictionary = _responses[id]
	_responses.erase(id)
	if entry.has("error"):
		var e: Dictionary = entry["error"]
		return _error(int(e.get("code", 0)), String(e.get("message", "")))
	var result: Variant = entry.get("result", {})
	return result as Dictionary if result is Dictionary else {"value": result}


## Submit a player intent. The sim validates; this client never pre-judges.
##
## Deliberately thin. Every temptation to "check first" here — is the player allowed
## through that door, is the target in range — is the stage deciding, and the sim
## already knows the answer and will give a reason with it.
func submit_action(verb: String, extras: Dictionary = {}) -> Dictionary:
	if _halted:
		return _error(ERR_SESSION_HALTED, _halt_reason)
	if not _has_baseline:
		return _error(ERR_NOT_SYNCED, "syncing: waiting for baseline snapshot before play input")
	var params := {"verb": verb}
	for k: String in extras:
		params[k] = extras[k]
	var seq_before := _applied_snapshot_seq
	var ticks_before := _tick_deltas_applied
	var result := await request(METHOD_SUBMIT_ACTION, params)
	if not result.get("__error__", false):
		_apply_commit_result(result, seq_before, ticks_before)
		await _verify_mirror_after_submit(result)
	return result


func advance(rounds: int = 1) -> Dictionary:
	if _halted:
		return _error(ERR_SESSION_HALTED, _halt_reason)
	if not _has_baseline:
		return _error(ERR_NOT_SYNCED, "syncing: waiting for baseline snapshot before play input")
	var seq_before := _applied_snapshot_seq
	var ticks_before := _tick_deltas_applied
	var result := await request(METHOD_ADVANCE, {"rounds": rounds})
	if not result.get("__error__", false):
		_apply_commit_result(result, seq_before, ticks_before)
		await _verify_mirror_after_submit(result)
	return result


func snapshot(params: Dictionary = {}) -> Dictionary:
	var result := await request(METHOD_SNAPSHOT, params)
	if not result.get("__error__", false):
		_replace_mirror_from_snapshot(result)
		_verify_snapshot_digest(result, "")
	return result


func _apply_commit_result(result: Dictionary, seq_before: int, ticks_before: int) -> void:
	_apply_tick_report(result)
	if not _has_baseline:
		return
	var res_seq := int(result.get("snapshotSeq", _applied_snapshot_seq))
	if res_seq != _applied_snapshot_seq:
		return
	# Apply delta once from RPC response when `sim/tick` did not already arrive during `await request`.
	if _applied_snapshot_seq == seq_before and _tick_deltas_applied == ticks_before:
		_mirror = StateDigest.apply_patches(_mirror, result.get("delta", []))
		_applied_via_rpc_queue.append(_delta_signature(result))


func _replace_mirror_from_snapshot(snap: Dictionary) -> void:
	_mirror = StateDigest.apply_patches({}, snap.get("delta", []))
	_has_baseline = true
	_applied_snapshot_seq = int(snap.get("snapshotSeq", _applied_snapshot_seq + 1))
	_applied_via_rpc_queue.clear()
	_apply_tick_report(snap)


static func _delta_signature(msg: Dictionary) -> Dictionary:
	return {
		"seq": int(msg.get("snapshotSeq", -1)),
		"tick": int(msg.get("tick", -1)),
		"canonical": String(msg.get("canonicalHash", "")),
		"hash": String(msg.get("hash", "")),
	}


# ── Position, mirror digest, and bounded resync ───────────────

func current_tick() -> int:
	return _tick


func hash_for_tick(tick: int) -> String:
	return String(_hash_by_tick.get(tick, ""))


func canonical_hash_for_tick(tick: int) -> String:
	return String(_canonical_by_tick.get(tick, ""))


func is_stale() -> bool:
	return _stale


func has_baseline() -> bool:
	return _has_baseline


func is_halted() -> bool:
	return _halted


func halt_reason() -> String:
	return _halt_reason


func last_attach_error() -> String:
	return _last_attach_error


func consecutive_resyncs() -> int:
	return _consecutive_resyncs


func total_resyncs() -> int:
	return _total_resyncs


func mismatch_log() -> Array[String]:
	return _mismatch_log.duplicate()


func mirror_digest() -> String:
	return StateDigest.canonical_state_hash(_mirror)


func mirror_state() -> Variant:
	return _mirror


## Authoritative player entity id from the mirrored snapshot (preferred so a live
## save load updates it) or from the `initialize` handshake response.
func player_id() -> String:
	if _mirror is Dictionary:
		var from_mirror := String((_mirror as Dictionary).get("playerId", "")).strip_edges()
		if not from_mirror.is_empty():
			return from_mirror
	return String(_handshake.get("playerId", "")).strip_edges()


func handshake() -> Dictionary:
	return _handshake.duplicate(true)


## Record the raw bytes of every message received, so a caller can compare two runs
## byte for byte. Must be set before `attach`. See `framing.gd`'s note: the parsed
## form cannot carry a byte-level claim, because Godot's JSON parse destroys the
## bytes before any comparison could see them.
func record_received_bytes() -> void:
	_framing.set("record_bodies", true)


## sha256 of everything received, or "" if recording was never enabled.
func received_digest() -> String:
	return String(_framing.call("body_digest"))


func received_byte_count() -> int:
	return int(_framing.call("recorded_body_bytes"))


## Ask the sim where it is, verify tick/hash parity and canonical mirror digest, and
## resync from the authoritative snapshot on mismatch (capped at 3 consecutive resyncs).
func verify_position() -> bool:
	if _halted:
		return false
	var snap := await request(METHOD_SNAPSHOT)
	if snap.get("__error__", false):
		_mark_stale("could not snapshot: %s" % snap.get("message", ""))
		return false

	var server_tick := int(snap.get("tick", -1))
	var server_hash := String(snap.get("hash", ""))
	var server_canonical := String(snap.get("canonicalHash", ""))
	var drift_reason := ""

	if server_tick != _tick:
		drift_reason = "tick drift: sim is at %d, stage believes %d" % [server_tick, _tick]
	else:
		var recorded := hash_for_tick(server_tick)
		if recorded.is_empty():
			drift_reason = "no recorded hash for tick %d — the stage never saw it" % server_tick
		elif recorded != server_hash:
			drift_reason = "state drift at tick %d: sim reports %s, stage recorded %s" % [server_tick, server_hash, recorded]

	var local_preimage := ""
	var local_digest := ""
	if _has_baseline:
		var local_res := StateDigest.try_canonical_json(_mirror)
		if bool(local_res.get("ok", false)):
			local_preimage = String(local_res["json"])
			local_digest = StateDigest.canonical_state_hash(_mirror)
		else:
			drift_reason = "canonical serialization error (%s): %s" % [local_res.get("code", ""), local_res.get("message", "")]
		if drift_reason.is_empty():
			if server_canonical.is_empty():
				drift_reason = "canonicalHash missing from snapshot at tick %d" % server_tick
			elif local_digest != server_canonical:
				drift_reason = "state drift at tick %d: canonical mirror %s != sim %s" % [server_tick, local_digest, server_canonical]

	if drift_reason.is_empty():
		_replace_mirror_from_snapshot(snap)
		if not _verify_snapshot_digest(snap, local_preimage):
			return false
		_consecutive_resyncs = 0
		_stale = false
		return true

	return _handle_mismatch_with_snapshot(server_tick, server_canonical, local_preimage, local_digest, drift_reason, snap)


func _verify_mirror_after_submit(result: Dictionary) -> bool:
	if _halted:
		return false
	if not _has_baseline:
		_mark_stale("syncing: cannot verify commit at tick %d before baseline snapshot has landed" % int(result.get("tick", _tick)))
		return false
	var tick := int(result.get("tick", _tick))
	var expected := String(result.get("canonicalHash", ""))
	var local_res := StateDigest.try_canonical_json(_mirror)
	var local_preimage := String(local_res.get("json", "")) if bool(local_res.get("ok", false)) else ""
	var local_digest := StateDigest.canonical_state_hash(_mirror) if bool(local_res.get("ok", false)) else ""
	var recorded_canon := String(_canonical_by_tick.get(tick, expected))

	if bool(local_res.get("ok", false)) and not expected.is_empty() and local_digest == expected and recorded_canon == expected:
		_consecutive_resyncs = 0
		_stale = false
		return true

	var reason := ""
	if not bool(local_res.get("ok", false)):
		reason = "canonical error (%s): %s" % [local_res.get("code", ""), local_res.get("message", "")]
	elif expected.is_empty():
		reason = "canonicalHash missing at tick %d" % tick
	else:
		reason = "state drift at tick %d: expected %s, mirror %s" % [tick, expected, local_digest]

	var snap := await request(METHOD_SNAPSHOT)
	if snap.get("__error__", false):
		var err_detail := "%s; resync snapshot failed: %s" % [reason, snap.get("message", "")]
		_mismatch_log.append(err_detail)
		_mark_stale(err_detail)
		_halt_session(err_detail)
		return false

	return _handle_mismatch_with_snapshot(tick, expected, local_preimage, local_digest, reason, snap)


func _handle_mismatch_with_snapshot(
	tick: int,
	expected: String,
	local_preimage: String,
	local_digest: String,
	reason: String,
	snap: Dictionary,
) -> bool:
	var fresh_mirror: Variant = StateDigest.apply_patches({}, snap.get("delta", []))
	var fresh_res := StateDigest.try_canonical_json(fresh_mirror)
	var fresh_preimage := String(fresh_res.get("json", "")) if bool(fresh_res.get("ok", false)) else ""
	var offset := StateDigest.first_diff_offset(local_preimage, fresh_preimage)
	if offset < 0:
		offset = 0

	_mirror = fresh_mirror
	_has_baseline = true
	_applied_snapshot_seq = int(snap.get("snapshotSeq", _applied_snapshot_seq + 1))
	_applied_via_rpc_queue.clear()
	_apply_tick_report(snap)

	_consecutive_resyncs += 1
	_total_resyncs += 1

	var snap_tick := int(snap.get("tick", tick))
	var snap_expected := String(snap.get("canonicalHash", expected))
	var fresh_hash_res := StateDigest.try_canonical_state_hash(_mirror)
	var fresh_digest := String(fresh_hash_res.get("hash", "")) if bool(fresh_hash_res.get("ok", false)) else ""

	var detail := "%s, first differing pre-image offset %d (resync %d/%d)" % [
		reason, offset, _consecutive_resyncs, MAX_CONSECUTIVE_RESYNCS,
	]
	_mismatch_log.append(detail)
	_mark_stale(detail)

	if not bool(fresh_hash_res.get("ok", false)) or snap_expected.is_empty() or fresh_digest != snap_expected:
		_halt_session("resync snapshot digest mismatch at tick %d: expected %s, mirror %s, first differing pre-image offset %d"
			% [snap_tick, snap_expected, fresh_digest, offset])
		return false

	if _consecutive_resyncs > MAX_CONSECUTIVE_RESYNCS:
		_halt_session("resync cap exceeded (%d consecutive mismatches, max %d): %s"
			% [_consecutive_resyncs, MAX_CONSECUTIVE_RESYNCS, detail])
		return false

	return false


func _verify_snapshot_digest(snap: Dictionary, prior_preimage: String) -> bool:
	var snap_tick := int(snap.get("tick", _tick))
	var snap_expected := String(snap.get("canonicalHash", ""))
	var fresh_json := StateDigest.try_canonical_json(_mirror)
	var fresh_digest := StateDigest.canonical_state_hash(_mirror) if bool(fresh_json.get("ok", false)) else ""
	if not bool(fresh_json.get("ok", false)) or snap_expected.is_empty() or fresh_digest != snap_expected:
		var offset := 0
		if not prior_preimage.is_empty() and bool(fresh_json.get("ok", false)):
			offset = maxi(0, StateDigest.first_diff_offset(prior_preimage, String(fresh_json["json"])))
		_halt_session("snapshot digest mismatch at tick %d: expected %s, mirror %s, first differing pre-image offset %d"
			% [snap_tick, snap_expected, fresh_digest, offset])
		return false
	return true


func _halt_session(reason: String) -> void:
	_halted = true
	_halt_reason = reason
	_stale = true
	if not suppress_ci_halt_marker:
		print("FAIL_SYNC_CAP: %s" % reason)
	if bus:
		bus.session_halted.emit(reason)


## Corrupt this client's own record, to prove drift detection and bounded resync fire.
##
## A detector that has only ever agreed is not a detector. Kept in production rather
## than a test helper for the same reason the engine keeps its RED controls in the
## suite: the thing being proven is a property of THIS code, and a copy in a test
## file proves it about the copy.
func _debug_corrupt_recorded_hash(tick: int) -> void:
	if _hash_by_tick.has(tick):
		_hash_by_tick[tick] = "0000000000000000000000000000dead"
	if _canonical_by_tick.has(tick):
		_canonical_by_tick[tick] = "0000000000000000000000000000dead"
	if _mirror is Dictionary:
		(_mirror as Dictionary)["__corrupt_probe__"] = "0000000000000000000000000000dead"


# ── Internals ─────────────────────────────────────────────────

func _alloc_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


func _write(message: Dictionary) -> void:
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var bytes := Framing.encode(message)
	var err := _peer.put_data(bytes)
	if err != OK:
		_report("write failed: %d" % err)


func _dispatch(msg: Dictionary) -> void:
	if msg.has("method"):
		var method := String(msg["method"])
		if method == NOTIFY_TICK:
			_on_tick(msg.get("params", {}) as Dictionary)
		elif method == NOTIFY_CLOSING:
			var params: Dictionary = msg.get("params", {}) as Dictionary
			_closing_reason = String(params.get("reason", ""))
			if bus:
				# A refusal and a shutdown arrive through the same notification. They
				# are different facts for a client — one means "try again later",
				# the other means "the world is gone" — so they are separated by the
				# only signal available: the reason the sim gave.
				if _closing_reason.contains("refused"):
					bus.refused.emit(_closing_reason)
				else:
					bus.disconnected.emit(_closing_reason)
		else:
			# Tolerant OUT (RFC 9413): an unknown notification is not an error. The
			# sim may learn to say things this client does not know yet.
			pass
		return

	if msg.has("id"):
		_responses[int(msg["id"])] = msg


func _on_tick(params: Dictionary) -> void:
	_apply_tick_report(params)
	if _has_baseline and int(params.get("snapshotSeq", -1)) == _applied_snapshot_seq:
		var sig := _delta_signature(params)
		if not _applied_via_rpc_queue.is_empty() and _applied_via_rpc_queue[0] == sig:
			_applied_via_rpc_queue.pop_front()
		else:
			_mirror = StateDigest.apply_patches(_mirror, params.get("delta", []))
			_tick_deltas_applied += 1
	if bus:
		bus.tick_received.emit(
			int(params.get("tick", -1)),
			String(params.get("hash", "")),
			params.get("events", []) as Array,
			params.get("delta", []) as Array,
		)
		for ev: Variant in params.get("events", []) as Array:
			if ev is Dictionary:
				bus.sim_event.emit(ev as Dictionary)


## Record the position reported by anything that carries one — a tick notification,
## a submitAction response, a snapshot. One code path, so the client's idea of where
## it is cannot depend on which message told it.
func _apply_tick_report(report: Dictionary) -> void:
	if not report.has("tick"):
		return
	var tick := int(report["tick"])
	var hash_value := String(report.get("hash", ""))
	var canonical_value := String(report.get("canonicalHash", ""))

	if not hash_value.is_empty():
		# `tick` is not a state version in this engine: advancing rounds can mutate the
		# world without incrementing `tick`, so position and canonical checks compare
		# against authoritative snapshots and per-commit `canonicalHash` values.
		_hash_by_tick[tick] = hash_value
	if not canonical_value.is_empty():
		_canonical_by_tick[tick] = canonical_value

	# Never move backwards. Responses and notifications can interleave, and a
	# response for an older tick must not rewind the client's position.
	if tick > _tick:
		_tick = tick


func _mark_stale(detail: String) -> void:
	_stale = true
	if bus:
		bus.staleness_detected.emit(detail)


func _report(detail: String) -> void:
	if bus:
		bus.transport_failed.emit(detail)


func _drop(reason: String) -> void:
	if not _connected:
		return
	_connected = false
	_peer.disconnect_from_host()
	if bus:
		bus.disconnected.emit(reason)


static func _error(code: int, message: String) -> Dictionary:
	return {"__error__": true, "code": code, "message": message}

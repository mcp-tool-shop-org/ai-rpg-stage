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
## WHAT IT MEANS TO VERIFY A HASH HERE, stated precisely because the honest version
## is narrower than it sounds. The sim's `stateHash` is
## `sha256(JSON.stringify(quantize(state)))` with JavaScript's insertion-order keys
## and JavaScript's number formatting. Godot's `JSON.stringify` sorts keys AND
## renders every parsed number as a float — measured on 4.7.stable:
## `{"tick":5}` round-trips to `{"tick":5.0}`. So this client CANNOT recompute that
## hash from its own mirror, and any code here claiming to would be lying.
##
## What it verifies instead is its POSITION: it records the hash the sim reported for
## each tick it applied, then asks for a fresh snapshot and requires the sim's
## reported tick and hash to equal what it recorded for where it believes it is. A
## dropped delta leaves this client's tick behind, and the check fires. That is a
## real detector for the failure that actually happens to a renderer — missing
## something — and it never pretends to be a byte-level audit of the mirror.
extends Node

const Framing := preload("res://client/framing.gd")

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

## Position: the last tick applied and the hash the sim reported for each tick.
var _tick := -1
var _hash_by_tick: Dictionary = {}
var _stale := false

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
	var err := _peer.connect_to_host(host, port)
	if err != OK:
		_report("connect_to_host(%s:%d) failed: %d" % [host, port, err])
		return {}

	# Small frames, sent immediately. Nagle would hold an intent back waiting for
	# company, which for an interactive client is latency for nothing.
	_peer.set_no_delay(true)

	var waited := 0
	while _peer.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		await polled
		waited += 1
		if waited > 6000:
			_report("timed out connecting to %s:%d" % [host, port])
			return {}

	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		# A refusal arrives as a `sim/closing` notification and then a close, so the
		# reason may already be here.
		_report("could not connect to %s:%d%s" % [host, port,
			"" if _closing_reason.is_empty() else " — " + _closing_reason])
		return {}

	var result: Dictionary = await request(METHOD_INITIALIZE, {
		"clientName": client_name,
		"clientVersion": client_version,
		# Declared honestly. `hashes` says this client checks what it can check and
		# reports staleness; it does not claim to recompute the sim's hash.
		"capabilities": {"notifications": true, "hashes": true},
	})
	if result.get("__error__", false):
		_report("initialize failed: %s" % result.get("message", "unknown"))
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


func is_attached() -> bool:
	return _connected and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED


func capabilities() -> Dictionary:
	return (_handshake.get("capabilities", {}) as Dictionary).duplicate()


func detach() -> void:
	if _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_write({"jsonrpc": "2.0", "id": _alloc_id(), "method": METHOD_SHUTDOWN, "params": {}})
	_peer.disconnect_from_host()
	_connected = false


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
	var params := {"verb": verb}
	for k: String in extras:
		params[k] = extras[k]
	var result := await request(METHOD_SUBMIT_ACTION, params)
	if not result.get("__error__", false):
		_apply_tick_report(result)
	return result


func snapshot() -> Dictionary:
	var result := await request(METHOD_SNAPSHOT)
	if not result.get("__error__", false):
		_apply_tick_report(result)
	return result


# ── Position and staleness ────────────────────────────────────

func current_tick() -> int:
	return _tick


func hash_for_tick(tick: int) -> String:
	return String(_hash_by_tick.get(tick, ""))


func is_stale() -> bool:
	return _stale


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


## Ask the sim where it is, and require it to agree with where this client thinks it
## is. Returns true when they agree.
##
## This is the honest form of "verify the hash" for a non-JS client (see the note at
## the top). It catches the failure a renderer actually suffers: having missed
## something. It does not claim to audit the mirror byte-for-byte, because it cannot.
func verify_position() -> bool:
	var snap := await request(METHOD_SNAPSHOT)
	if snap.get("__error__", false):
		_mark_stale("could not snapshot: %s" % snap.get("message", ""))
		return false

	var server_tick := int(snap.get("tick", -1))
	var server_hash := String(snap.get("hash", ""))

	if server_tick != _tick:
		_mark_stale("tick drift: sim is at %d, stage believes %d" % [server_tick, _tick])
		return false

	var recorded := hash_for_tick(server_tick)
	if recorded.is_empty():
		_mark_stale("no recorded hash for tick %d — the stage never saw it" % server_tick)
		return false
	if recorded != server_hash:
		_mark_stale("state drift at tick %d: sim reports %s, stage recorded %s"
			% [server_tick, server_hash, recorded])
		return false

	return true


## Corrupt this client's own record, to prove `verify_position` can fire.
##
## A detector that has only ever agreed is not a detector. Kept in production rather
## than a test helper for the same reason the engine keeps its RED controls in the
## suite: the thing being proven is a property of THIS code, and a copy in a test
## file proves it about the copy.
func _debug_corrupt_recorded_hash(tick: int) -> void:
	if _hash_by_tick.has(tick):
		_hash_by_tick[tick] = "0000000000000000000000000000dead"


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

	if not hash_value.is_empty():
		if _hash_by_tick.has(tick) and String(_hash_by_tick[tick]) != hash_value:
			# The same tick, two different hashes. The sim is deterministic, so this
			# cannot happen unless this client's bookkeeping is wrong or the stream
			# was tampered with. Either way it is stale, and it does not "pick one".
			_mark_stale("tick %d reported two different hashes: %s then %s"
				% [tick, _hash_by_tick[tick], hash_value])
		_hash_by_tick[tick] = hash_value

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

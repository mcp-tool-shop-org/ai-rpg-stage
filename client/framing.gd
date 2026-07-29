## framing.gd — Content-Length framed JSON-RPC, the GDScript half.
##
## The mirror of the engine's `packages/sidecar/src/framing.ts`. LSP's framing: a
## byte-length prefix, then the body. Chosen there because a JSON document can
## contain newlines and a length prefix cannot be confused by content.
##
## Three things this file gets right on purpose, because each is a way framing
## breaks that looks like something else entirely:
##
##   1. **BYTE length, not character length.** A single multi-byte character makes a
##      character-counted header under-declare the frame, and the reader
##      desynchronises PERMANENTLY — every subsequent message is garbage. The
##      symptom (malformed JSON) looks nothing like the cause.
##
##   2. **Messages split across arbitrary chunk boundaries.** TCP does not deliver
##      messages, it delivers bytes. A reader that assumes one `get_data` is one
##      message works perfectly until a frame straddles a packet, which under load
##      is always. Tested by feeding the reader one byte at a time.
##
##   3. **A hard ceiling.** Matching the engine's 16 MiB, so a broken or hostile
##      peer cannot make this process buffer without bound.
##
## PackedByteArray throughout. Going through String would re-encode the payload and
## put us back in problem 1.
extends RefCounted

## Matches MAX_MESSAGE_BYTES in the engine's framing.ts. Far above any real
## snapshot, far below anything that threatens the process.
const MAX_MESSAGE_BYTES := 16 * 1024 * 1024

const _CR := 13
const _LF := 10

var _buffer := PackedByteArray()
var _errors: Array[String] = []

## When set, every decoded message's RAW BODY BYTES are kept so a caller can hash
## exactly what arrived.
##
## This exists because of a measured limitation. Godot's JSON is not byte-preserving:
## `JSON.parse_string` renders every number as a float and `JSON.stringify` sorts
## keys, so `{"tick":5}` round-trips to `{"tick":5.0}` with a different key order.
## A client therefore cannot make a byte-level claim about a simulation stream from
## its PARSED form — the parse has already destroyed the bytes. Keeping the raw
## bodies is the only way for the stage to say "I received exactly this, twice."
##
## Off by default: a long session would accumulate every byte it ever received.
var record_bodies := false
var _bodies := PackedByteArray()


## Encode one message, header and body, ready to write to a stream.
static func encode(message: Dictionary) -> PackedByteArray:
	var body := JSON.stringify(message).to_utf8_buffer()
	var out := ("Content-Length: %d\r\n\r\n" % body.size()).to_ascii_buffer()
	out.append_array(body)
	return out


## Feed bytes in. Returns whole messages, in order, zero or more per call.
func push(chunk: PackedByteArray) -> Array[Dictionary]:
	_buffer.append_array(chunk)
	var out: Array[Dictionary] = []

	while true:
		var sep := _find_header_end(_buffer)
		if sep < 0:
			# No complete header yet. Guard the header itself: without this a peer
			# that never sends \r\n\r\n makes the buffer grow forever.
			if _buffer.size() > MAX_MESSAGE_BYTES:
				_fail("oversize", "no header terminator within %d bytes" % MAX_MESSAGE_BYTES)
				_buffer = PackedByteArray()
			break

		var header := _buffer.slice(0, sep).get_string_from_ascii()
		var length := _content_length(header)
		if length < 0:
			# An unparseable header cannot be resynchronised from — the stream
			# position is unknown. Drop the connection's buffer and say so, rather
			# than guessing an offset and producing plausible garbage.
			_fail("malformed-header", header.replace("\r\n", "\\r\\n"))
			_buffer = PackedByteArray()
			break
		if length > MAX_MESSAGE_BYTES:
			_fail("oversize", "declared %d bytes" % length)
			_buffer = PackedByteArray()
			break

		var body_start := sep + 4
		if _buffer.size() < body_start + length:
			break # the body has not fully arrived — wait for more bytes

		var body_bytes := _buffer.slice(body_start, body_start + length)
		var body := body_bytes.get_string_from_utf8()
		_buffer = _buffer.slice(body_start + length)
		if record_bodies:
			_bodies.append_array(body_bytes)

		var parsed: Variant = JSON.parse_string(body)
		if parsed is Dictionary:
			out.append(parsed as Dictionary)
		else:
			# The frame was well-formed; its contents were not. Recoverable, because
			# the length told us exactly where the next message starts.
			_fail("parse-error", body.substr(0, 120))

	return out


## Framing faults seen so far. Non-empty is a defect, never routine.
func errors() -> Array[String]:
	return _errors.duplicate()


func buffered_bytes() -> int:
	return _buffer.size()


## sha256 over every raw body byte decoded so far. Empty when `record_bodies` is off,
## which is stated rather than silently returning the hash of nothing — a digest of
## an empty buffer would compare equal across two runs that recorded nothing at all,
## and that is a vacuous pass waiting to happen.
func body_digest() -> String:
	if not record_bodies:
		return ""
	if _bodies.is_empty():
		return ""
	# HashingContext, not `String.sha256_text()`: hashing the DECODED string would
	# hash Godot's re-encoding of the bytes rather than the bytes, which is the exact
	# fidelity loss this function exists to route around. (`sha256_text` is a String
	# method and does not exist on PackedByteArray — a first draft here called it and
	# failed to compile, which the runner reported as a red suite rather than a skip.)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(_bodies)
	return ctx.finish().hex_encode()


func recorded_body_bytes() -> int:
	return _bodies.size()


func _fail(kind: String, detail: String) -> void:
	_errors.append("%s: %s" % [kind, detail])


## Index of the first \r\n\r\n, or -1.
##
## Hand-rolled because `PackedByteArray.find` searches for a single byte value, not
## a subsequence. Converting to String to use `String.find` would decode the body
## as text before we know its length, which is exactly the mistake this module is
## built to avoid.
static func _find_header_end(buf: PackedByteArray) -> int:
	var n := buf.size()
	var i := 0
	while i + 3 < n:
		if buf[i] == _CR and buf[i + 1] == _LF and buf[i + 2] == _CR and buf[i + 3] == _LF:
			return i
		i += 1
	return -1


## Parse `Content-Length` out of a header block, or -1.
##
## Case-insensitive on the field name (HTTP-style headers are, and a peer is not
## obliged to match our casing) and tolerant of extra fields, which is the tolerant
## half of RFC 9413 applied where it belongs: to what we RECEIVE.
static func _content_length(header: String) -> int:
	for line: String in header.split("\r\n", false):
		var colon := line.find(":")
		if colon < 0:
			continue
		if line.substr(0, colon).strip_edges().to_lower() != "content-length":
			continue
		var raw := line.substr(colon + 1).strip_edges()
		if not raw.is_valid_int():
			return -1
		var value := raw.to_int()
		return value if value >= 0 else -1
	return -1

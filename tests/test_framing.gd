## test_framing.gd — the Content-Length codec, including the cases that hide bugs.
##
## Framing is where a wire fails in the least helpful way possible: the symptom is
## garbled JSON several messages later and the cause is an off-by-one in a header
## nobody looked at. So the cases here are chosen to be the ones that only show up
## under load — a multi-byte payload, and a frame delivered one byte at a time.
extends RefCounted

const Framing := preload("res://client/framing.gd")


func run(t: RefCounted) -> void:
	_round_trip(t)
	_multibyte(t)
	_split_delivery(t)
	_multiple_per_chunk(t)
	_header_tolerance(t)
	_malformed(t)
	_oversize(t)


func _round_trip(t: RefCounted) -> void:
	var msg := {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"clientName": "stage"}}
	var f: RefCounted = Framing.new()
	var out: Array = f.call("push", Framing.encode(msg))
	t.equals(out.size(), 1, "one encoded message decodes to one message")
	if out.size() == 1:
		t.equals((out[0] as Dictionary)["method"], "initialize", "the method survives the round trip")
		t.equals(int((out[0] as Dictionary)["id"]), 1, "the id survives the round trip")
	t.equals(f.call("errors"), [] as Array[String], "a clean round trip logs no framing errors")


func _multibyte(t: RefCounted) -> void:
	# The bug this catches: a header counting CHARACTERS instead of BYTES
	# under-declares the frame, and the reader desynchronises permanently. Every
	# string here is one a real world could contain — a refusal spoken by a person.
	var reason := "«Ingen går ner utan rep.» — 三人必要 · ✋"
	var msg := {"jsonrpc": "2.0", "id": 7, "result": {"reason": reason}}
	var encoded := Framing.encode(msg)

	var header_end := -1
	for i in range(encoded.size() - 3):
		if encoded[i] == 13 and encoded[i + 1] == 10 and encoded[i + 2] == 13 and encoded[i + 3] == 10:
			header_end = i
			break
	t.check(header_end > 0, "the encoded frame has a header terminator")

	var header := encoded.slice(0, header_end).get_string_from_ascii()
	var declared := header.split(":")[1].strip_edges().to_int()
	var actual_body_bytes := encoded.size() - (header_end + 4)
	t.equals(declared, actual_body_bytes, "Content-Length counts BYTES, not characters")
	t.not_equals(declared, JSON.stringify(msg).length(), "and byte length differs from character length here")

	var f: RefCounted = Framing.new()
	var out: Array = f.call("push", encoded)
	t.equals(out.size(), 1, "a multi-byte payload decodes to one message")
	if out.size() == 1:
		var got: Dictionary = (out[0] as Dictionary)["result"]
		t.equals(String(got["reason"]), reason, "the multi-byte text survives byte-exact")


func _split_delivery(t: RefCounted) -> void:
	# TCP delivers bytes, not messages. A reader that assumes one read is one message
	# works right up until a frame straddles a packet, which under load is always.
	# One byte at a time is the worst case and the cheapest to test.
	var msg := {"jsonrpc": "2.0", "method": "sim/tick", "params": {"tick": 3, "hash": "abc", "events": []}}
	var encoded := Framing.encode(msg)
	var f: RefCounted = Framing.new()

	var decoded: Array[Dictionary] = []
	for i in range(encoded.size()):
		var one := PackedByteArray()
		one.append(encoded[i])
		for m: Dictionary in f.call("push", one) as Array:
			decoded.append(m)

	t.equals(decoded.size(), 1, "a frame delivered one byte at a time decodes exactly once")
	if decoded.size() == 1:
		t.equals(String(decoded[0]["method"]), "sim/tick", "and arrives intact")
	t.equals(int(f.call("buffered_bytes")), 0, "nothing is left buffered afterwards")
	t.equals(f.call("errors"), [] as Array[String], "and no framing error was logged")


func _multiple_per_chunk(t: RefCounted) -> void:
	# The other half of the same problem: several messages in ONE read. A reader that
	# handles only the first leaves the rest buffered until the next arrival, which
	# looks like unexplained latency.
	var a := Framing.encode({"id": 1, "result": {"n": 1}})
	var b := Framing.encode({"id": 2, "result": {"n": 2}})
	var c := Framing.encode({"method": "sim/tick", "params": {"tick": 1}})
	var joined := PackedByteArray()
	joined.append_array(a)
	joined.append_array(b)
	joined.append_array(c)

	var f: RefCounted = Framing.new()
	var out: Array = f.call("push", joined)
	t.equals(out.size(), 3, "three frames in one chunk decode to three messages")
	if out.size() == 3:
		t.equals(int((out[0] as Dictionary)["id"]), 1, "in order: first")
		t.equals(int((out[1] as Dictionary)["id"]), 2, "in order: second")
		t.equals(String((out[2] as Dictionary)["method"]), "sim/tick", "in order: third")


func _header_tolerance(t: RefCounted) -> void:
	# Tolerant about what we RECEIVE (RFC 9413's tolerant half), where it costs
	# nothing: header casing is not ours to dictate, and an extra field is harmless.
	var body := JSON.stringify({"id": 9, "result": {}}).to_utf8_buffer()
	var raw := ("content-length: %d\r\nX-Note: from-a-peer\r\n\r\n" % body.size()).to_ascii_buffer()
	raw.append_array(body)

	var f: RefCounted = Framing.new()
	var out: Array = f.call("push", raw)
	t.equals(out.size(), 1, "lowercase header name and an extra field are accepted")
	t.equals(f.call("errors"), [] as Array[String], "and logged as no error")


func _malformed(t: RefCounted) -> void:
	# An unparseable header cannot be resynchronised from: the stream position is
	# unknown. It must be REPORTED, not guessed at — guessing produces plausible
	# garbage, which is worse than a loud stop.
	var bad := "Content-Length: not-a-number\r\n\r\n{}".to_utf8_buffer()
	var f: RefCounted = Framing.new()
	var out: Array = f.call("push", bad)
	t.equals(out.size(), 0, "a malformed header yields no messages")
	t.equals((f.call("errors") as Array).size(), 1, "and is reported exactly once")
	t.contains(String((f.call("errors") as Array)[0]), "malformed-header", "with its kind named")

	# A well-formed frame whose BODY is not JSON is recoverable — the length told us
	# where the next message starts — so it reports and carries on.
	var body := "not json at all".to_utf8_buffer()
	var frame := ("Content-Length: %d\r\n\r\n" % body.size()).to_ascii_buffer()
	frame.append_array(body)
	frame.append_array(Framing.encode({"id": 5, "result": {"ok": true}}))

	var g: RefCounted = Framing.new()
	var out2: Array = g.call("push", frame)
	t.equals(out2.size(), 1, "a bad body is skipped and the NEXT message still arrives")
	t.contains(String((g.call("errors") as Array)[0]), "parse-error", "the bad body is reported as a parse error")


func _oversize(t: RefCounted) -> void:
	# The ceiling exists so a broken or hostile peer cannot make the process buffer
	# without bound. Declared-oversize is the cheap case to prove.
	var huge := "Content-Length: 99999999999\r\n\r\n".to_utf8_buffer()
	var f: RefCounted = Framing.new()
	var out: Array = f.call("push", huge)
	t.equals(out.size(), 0, "an oversize declaration yields no messages")
	t.contains(String((f.call("errors") as Array)[0]), "oversize", "and is reported as oversize")
	t.equals(int(f.call("buffered_bytes")), 0, "and the buffer is cleared rather than left to grow")

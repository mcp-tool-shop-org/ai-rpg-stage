## state_digest.gd — RFC 6902/Wire-patch application and canonical state digest (spec v2).
##
## Matches @ai-rpg-engine/sidecar's `canonicalJson` / `canonicalStateHash` byte-for-byte:
##   * Every number is scaled by 1e6 in IEEE-754 binary64, rounded half-away-from-zero,
##     bounded to safe integers (±9,007,199,254.740991 -> ±2^53 - 1), and written as
##     plain decimal integer digits (`-0` writes as `0`) — never Godot float formatting.
##   * Object keys must be non-NUL ASCII, sorted lexicographically by code unit order.
##   * Explicit `null` object values are retained.
##   * NUL code points, lone surrogates, non-finite numbers, and non-JSON runtime types
##     return structured errors rather than partial output.
extends RefCounted

const DIGEST_SPEC_VERSION := 2
const DIGEST_SCALE := 1000000.0
const MAX_SAFE_INTEGER_F := 9007199254740991.0


static func apply_patches(target: Variant, patches: Variant) -> Variant:
	var root: Variant = target
	if typeof(patches) != TYPE_ARRAY:
		return root
	for patch_v: Variant in (patches as Array):
		if not (patch_v is Dictionary):
			continue
		var patch := patch_v as Dictionary
		var op := str(patch.get("op", "set"))
		var raw_path: Variant = patch.get("path", [])
		var segments: Variant = _parse_path(raw_path)
		if segments == null:
			continue
		var path := segments as Array
		if path.is_empty():
			if op == "remove":
				root = null
			else:
				root = _clone_value(patch.get("value", null))
			continue

		if _has_forbidden_segment(path):
			continue

		var parent: Variant = _resolve_parent(root, path)
		if parent == null:
			continue

		var key: Variant = path[path.size() - 1]
		if op == "remove":
			if parent is Array:
				var idx := _array_index(key, (parent as Array).size(), false)
				if idx >= 0 and idx < (parent as Array).size():
					(parent as Array).remove_at(idx)
			elif parent is Dictionary:
				(parent as Dictionary).erase(str(key))
		else:
			var val: Variant = _clone_value(patch.get("value", null))
			if parent is Array:
				var arr := parent as Array
				if str(key) == "-":
					arr.append(val)
				else:
					var idx := int(key)
					if idx >= 0:
						while arr.size() <= idx:
							arr.append(null)
						arr[idx] = val
			elif parent is Dictionary:
				(parent as Dictionary)[str(key)] = val
	return root


static func try_canonical_json(value: Variant) -> Dictionary:
	var err := {"ok": true}
	var out: Variant = _write_canonical(value, err)
	if out == null or not bool(err.get("ok", true)):
		return {
			"ok": false,
			"code": str(err.get("code", "CANONICAL_ERROR")),
			"message": str(err.get("message", "canonical JSON serialization failed")),
		}
	return {"ok": true, "json": str(out)}


static func canonical_json(value: Variant) -> String:
	var res := try_canonical_json(value)
	return str(res["json"]) if bool(res.get("ok", false)) else ""


static func try_canonical_state_hash(state: Variant) -> Dictionary:
	var res := try_canonical_json(state)
	if not bool(res.get("ok", false)):
		return res
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(str(res["json"]).to_utf8_buffer())
	return {"ok": true, "hash": ctx.finish().hex_encode().substr(0, 32)}


static func canonical_state_hash(state: Variant) -> String:
	var res := try_canonical_state_hash(state)
	return str(res["hash"]) if bool(res.get("ok", false)) else ""


## First UTF-8 byte offset where two canonical pre-images differ, or -1 if identical.
static func first_diff_offset(a: String, b: String) -> int:
	var ba := a.to_utf8_buffer()
	var bb := b.to_utf8_buffer()
	var limit := mini(ba.size(), bb.size())
	for i in range(limit):
		if ba[i] != bb[i]:
			return i
	if ba.size() != bb.size():
		return limit
	return -1


static func _parse_path(raw_path: Variant) -> Variant:
	if raw_path is Array:
		return raw_path
	if raw_path is String:
		var ptr := raw_path as String
		if ptr.is_empty():
			return []
		if not ptr.begins_with("/"):
			return null
		var parts := ptr.substr(1).split("/", true)
		var out: Array = []
		for seg in parts:
			var unescaped := seg.replace("~1", "/").replace("~0", "~")
			if unescaped.is_valid_int() and not (unescaped.length() > 1 and unescaped.begins_with("0")):
				out.append(int(unescaped))
			else:
				out.append(unescaped)
		return out
	return null


static func _has_forbidden_segment(path: Array) -> bool:
	for seg: Variant in path:
		var s := str(seg)
		if s == "__proto__" or s == "constructor" or s == "prototype":
			return true
	return false


static func _array_index(key: Variant, size: int, allow_append: bool) -> int:
	if allow_append and str(key) == "-":
		return size
	if typeof(key) == TYPE_INT or typeof(key) == TYPE_FLOAT:
		return int(key)
	var s := str(key)
	if s.is_valid_int():
		return int(s)
	return -1


static func _clone_value(v: Variant) -> Variant:
	if v is Dictionary:
		return (v as Dictionary).duplicate(true)
	if v is Array:
		return (v as Array).duplicate(true)
	return v


static func _resolve_parent(root: Variant, path: Array) -> Variant:
	var node: Variant = root
	for i in range(path.size() - 1):
		if not (node is Dictionary) and not (node is Array):
			return null
		var key: Variant = path[i]
		var next: Variant = null
		if node is Array:
			var arr := node as Array
			var idx := _array_index(key, arr.size(), false)
			if idx >= 0 and idx < arr.size():
				next = arr[idx]
		else:
			next = (node as Dictionary).get(str(key), null)
		if next == null:
			var nxt_key: Variant = path[i + 1]
			if typeof(nxt_key) == TYPE_FLOAT or typeof(nxt_key) == TYPE_INT:
				next = []
			else:
				next = {}
			if node is Array:
				var arr := node as Array
				var idx := int(key)
				while arr.size() <= idx:
					arr.append(null)
				arr[idx] = next
			else:
				(node as Dictionary)[str(key)] = next
		node = next
	return node


static func _fail_canonical(err: Variant, code: String, msg: String) -> Variant:
	if err is Dictionary:
		var err_dict := err as Dictionary
		if not err_dict.has("ok") or bool(err_dict.get("ok", true)):
			err_dict["ok"] = false
			err_dict["code"] = code
			err_dict["message"] = msg
	return null


static func _escape_json_string(s: String, err: Variant = null) -> Variant:
	var out := "\""
	for i in range(s.length()):
		var cp := s.unicode_at(i)
		match cp:
			0x22:
				out += "\\\""
			0x5C:
				out += "\\\\"
			0x08:
				out += "\\b"
			0x0C:
				out += "\\f"
			0x0A:
				out += "\\n"
			0x0D:
				out += "\\r"
			0x09:
				out += "\\t"
			_:
				if cp == 0x0000:
					return _fail_canonical(err, "NUL_CHARACTER", "NUL/lone-surrogate rule (NUL_CHARACTER): U+0000 is invalid in canonical JSON")
				elif cp < 0 or cp > 0x10FFFF:
					return _fail_canonical(err, "INVALID_CODEPOINT", "invalid Unicode scalar %d in canonical JSON" % cp)
				elif cp >= 0xD800 and cp <= 0xDFFF:
					return _fail_canonical(err, "LONE_SURROGATE", "NUL/lone-surrogate rule (LONE_SURROGATE): lone surrogate U+%04X is invalid in canonical JSON" % cp)
				elif cp < 0x20:
					out += "\\u%04x" % cp
				else:
					out += char(cp)
	out += "\""
	return out


static func _write_canonical(value: Variant, err: Variant = null) -> Variant:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT, TYPE_FLOAT:
			var f := float(value)
			if is_nan(f) or is_inf(f):
				return _fail_canonical(err, "NON_FINITE_NUMBER", "JSON-number rule (NON_FINITE_NUMBER): non-finite number is invalid in canonical JSON")
			var scaled: float = f * DIGEST_SCALE
			if is_nan(scaled) or is_inf(scaled) or absf(scaled) > MAX_SAFE_INTEGER_F or absf(roundf(scaled)) > MAX_SAFE_INTEGER_F:
				return _fail_canonical(err, "UNSAFE_SCALED_INTEGER", "integer-range rule (UNSAFE_SCALED_INTEGER): scaled number exceeds safe integer bound (2^53 - 1)")
			var rounded: int = int(roundf(scaled))
			return "0" if rounded == 0 else str(rounded)
		TYPE_STRING:
			return _escape_json_string(value, err)
		TYPE_ARRAY:
			var parts := PackedStringArray()
			for item: Variant in (value as Array):
				var written: Variant = _write_canonical(item, err)
				if written == null:
					return null
				parts.append(str(written))
			return "[" + ",".join(parts) + "]"
		TYPE_DICTIONARY:
			var dict := value as Dictionary
			var pairs: Array = []
			for k: Variant in dict.keys():
				var k_str := str(k)
				for ki in range(k_str.length()):
					var kcp := k_str.unicode_at(ki)
					if kcp == 0x0000:
						return _fail_canonical(err, "NUL_CHARACTER", "ASCII-key rule (NUL_CHARACTER): object key contains U+0000")
					if kcp > 0x7F:
						return _fail_canonical(err, "NON_ASCII_KEY", "ASCII-key rule (NON_ASCII_KEY): object key contains non-ASCII character U+%04X" % kcp)
				pairs.append([k_str, k])
			pairs.sort_custom(func(a: Array, b: Array) -> bool: return String(a[0]) < String(b[0]))
			var parts := PackedStringArray()
			for pair: Array in pairs:
				var k_str: String = pair[0]
				var orig_k: Variant = pair[1]
				var v: Variant = dict[orig_k]
				var ek: Variant = _escape_json_string(k_str, err)
				if ek == null:
					return null
				var ev: Variant = _write_canonical(v, err)
				if ev == null:
					return null
				parts.append(str(ek) + ":" + str(ev))
			return "{" + ",".join(parts) + "}"
		_:
			return _fail_canonical(err, "UNSUPPORTED_VALUE_TYPE", "JSON-value rule (UNSUPPORTED_VALUE_TYPE): unsupported Variant type %d in canonical JSON" % typeof(value))

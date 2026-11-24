## test_event_manifest.gd — verifies client/event_manifest.json covers every type
## exported by the pinned engine's ENGINE_EVENT_TYPES, enforces todo expiry, and proves
## every `handled` entry produces a visible bespoke transcript or scene effect on replay.
extends RefCounted

const Harness := preload("res://tools/sidecar_harness.gd")
const Diorama := preload("res://stage/diorama.gd")
const NetworkClient := preload("res://client/network_client.gd")
const EventBus := preload("res://client/event_bus.gd")
const Session := preload("res://stage/session.gd")

const MANIFEST_PATH := "res://client/event_manifest.json"
const REPLAY_FIXTURE_PATH := "res://fixtures/handled_events_replay.json"


func run_async(t: RefCounted) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		t.check(false, "SceneTree available")
		return

	var engine_types := _load_engine_event_types(t)
	if engine_types.is_empty():
		return

	_test_vocabulary_parser_cases(t)

	t.is_true(FileAccess.file_exists(MANIFEST_PATH), "stage event manifest exists")
	var manifest_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	t.check(manifest_v is Dictionary, "event manifest parses as JSON object")
	if not (manifest_v is Dictionary):
		return
	var manifest := manifest_v as Dictionary

	t.is_true(FileAccess.file_exists(REPLAY_FIXTURE_PATH), "handled-event replay fixture exists")
	var replay_doc_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(REPLAY_FIXTURE_PATH))
	t.check(replay_doc_v is Dictionary, "replay fixture parses as JSON object")
	if not (replay_doc_v is Dictionary):
		return

	var replay_results := await _replay_handled_events(t, tree, (replay_doc_v as Dictionary).get("events", []) as Array)
	var today_iso := Time.get_date_string_from_system()
	var live_errors := validate_manifest(engine_types, manifest, today_iso, replay_results)
	t.equals(live_errors.size(), 0,
		"all %d engine event types pass manifest gate without error%s" % [
			engine_types.size(),
			"" if live_errors.is_empty() else ": " + "; ".join(live_errors),
		])

	var handled_count := 0
	var todo_count := 0
	for key: Variant in manifest.keys():
		var entry := manifest[key] as Dictionary
		if String(entry.get("status", "")) == "handled":
			handled_count += 1
		elif String(entry.get("status", "")) == "todo":
			todo_count += 1
	t.equals(handled_count, Session.RENDERED.size(), "all Session.RENDERED types are marked handled")
	t.equals(handled_count + todo_count, engine_types.size(), "every remaining engine type is seeded as todo")
	t.equals(manifest.size(), engine_types.size(), "event_manifest.json count matches ENGINE_EVENT_TYPES count exactly")

	# ── RED Controls ──────────────────────────────────────────

	# 1. Missing engine event type fails.
	var missing_manifest := manifest.duplicate(true)
	missing_manifest.erase(engine_types[0])
	var missing_errs := validate_manifest(engine_types, missing_manifest, today_iso, replay_results)
	t.check(missing_errs.size() >= 1 and missing_errs[0].contains("missing engine event type"),
		"RED: engine type missing from manifest fails")

	# 2. Extra manifest entry absent from engine list fails.
	var extra_manifest := manifest.duplicate(true)
	extra_manifest["bogus.not.in.engine"] = {"status": "todo", "owner": "stage", "expiry": "2027-01-15"}
	var extra_errs := validate_manifest(engine_types, extra_manifest, today_iso, replay_results)
	var saw_extra := false
	for err: String in extra_errs:
		if err.contains("manifest event type not in engine list") and err.contains("bogus.not.in.engine"):
			saw_extra = true
	t.is_true(saw_extra, "RED: manifest entry not in engine list fails")

	# 3. Expired todo entry fails.
	var expired_manifest := manifest.duplicate(true)
	var sample_todo := ""
	for et: String in engine_types:
		if String((expired_manifest[et] as Dictionary).get("status", "")) == "todo":
			sample_todo = et
			break
	expired_manifest[sample_todo] = {"status": "todo", "owner": "stage", "expiry": "2020-01-01"}
	var exp_errs := validate_manifest(engine_types, expired_manifest, today_iso, replay_results)
	var saw_expired := false
	for err: String in exp_errs:
		if err.contains("expired todo entry") and err.contains(sample_todo):
			saw_expired = true
	t.is_true(saw_expired, "RED: expired todo entry fails")

	# 4. Handled entry producing zero transcript or scene change on replay fails.
	var noop_results := await _replay_handled_events(t, tree, [{"type": "action.rejected", "payload": {}}])
	var noop_entry: Dictionary = noop_results.get("action.rejected", {}) as Dictionary
	t.equals(int(noop_entry.get("bespoke_transcript_lines", -1)), 0,
		"no-op fixture replay emits zero transcript lines")
	t.is_false(bool(noop_entry.get("scene_changed", true)),
		"no-op fixture replay makes zero scene changes")
	var merged_results := replay_results.duplicate(true)
	merged_results["action.rejected"] = noop_entry
	var noop_errs := validate_manifest(engine_types, manifest, today_iso, merged_results)
	var saw_noop := false
	for err: String in noop_errs:
		if err.contains("handled event type changed nothing on replay") and err.contains("action.rejected"):
			saw_noop = true
	t.is_true(saw_noop, "RED: handled type that changes nothing on replay fails")

	# 5. no-visible-effect requires a non-empty reason (and passes when given one).
	var nve_bad := manifest.duplicate(true)
	nve_bad[sample_todo] = {"status": "no-visible-effect", "reason": ""}
	var nve_bad_errs := validate_manifest(engine_types, nve_bad, today_iso, replay_results)
	t.check(nve_bad_errs.size() >= 1, "RED: no-visible-effect without reason fails")
	var nve_ok := manifest.duplicate(true)
	nve_ok[sample_todo] = {"status": "no-visible-effect", "reason": "diagnostic-only event"}
	var nve_ok_errs := validate_manifest(engine_types, nve_ok, today_iso, replay_results)
	t.equals(nve_ok_errs.size(), 0, "no-visible-effect with non-empty reason passes")


func _load_engine_event_types(t: RefCounted) -> Array[String]:
	var engine_dir := Harness.find_engine_dir()
	var ts_path := engine_dir + "/packages/core/src/event-vocabulary.ts"
	var js_path := engine_dir + "/packages/core/dist/event-vocabulary.js"
	var src_path := ts_path if FileAccess.file_exists(ts_path) else js_path
	t.is_true(FileAccess.file_exists(src_path),
		"pinned engine event vocabulary exists (%s)" % src_path)
	if not FileAccess.file_exists(src_path):
		return []

	var text := FileAccess.get_file_as_string(src_path)
	var parsed := parse_engine_event_types_source(text)
	var errs: Array = parsed.get("errors", []) as Array
	t.check(bool(parsed.get("ok", false)) and errs.is_empty(),
		"source parser parsed ENGINE_EVENT_TYPES without errors",
		"; ".join(PackedStringArray(errs)))
	var out: Array[String] = []
	for item: Variant in (parsed.get("types", []) as Array):
		out.append(String(item))

	var exported_types := _load_runtime_engine_event_types(t, engine_dir)
	t.equals(out.size(), exported_types.size(),
		"parsed ENGINE_EVENT_TYPES count equals pinned engine export (%d)" % exported_types.size())
	t.equals(out, exported_types, "parsed ENGINE_EVENT_TYPES matches pinned engine export exactly")
	return out


func _test_vocabulary_parser_cases(t: RefCounted) -> void:
	var dq_src := "export const ENGINE_EVENT_TYPES = [\n  \"alpha.one\",\n  \"beta.two\",\n] as const;\n"
	var dq := parse_engine_event_types_source(dq_src)
	t.is_true(bool(dq.get("ok", false)), "double-quoted ENGINE_EVENT_TYPES parses cleanly")
	var expected_dq: Array[String] = ["alpha.one", "beta.two"]
	t.equals(dq.get("types", []), expected_dq, "double-quoted entries preserved in exact order")

	var mix_src := "export const ENGINE_EVENT_TYPES = [\n  // line comment\n  'single.one',\n  \"double.two\", /* block */\n  'single.three',\n];\n"
	var mix := parse_engine_event_types_source(mix_src)
	t.is_true(bool(mix.get("ok", false)), "mixed single- and double-quoted ENGINE_EVENT_TYPES parses cleanly")
	var expected_mix: Array[String] = ["single.one", "double.two", "single.three"]
	t.equals(mix.get("types", []), expected_mix, "mixed-quote entries preserved with comments stripped")

	var ts_typed_src := "export const ENGINE_EVENT_TYPES: readonly string[] = [\n  \"alpha.one\",\n  'beta.two',\n] as const;\n"
	var ts_typed := parse_engine_event_types_source(ts_typed_src)
	t.is_true(bool(ts_typed.get("ok", false)), "typed TS array annotation with mixed quotes parses cleanly")
	t.equals(ts_typed.get("types", []), expected_dq, "typed TS annotation preserves exact entries")

	for bad_case: Dictionary in [
		{"label": "unquoted identifier", "src": "export const ENGINE_EVENT_TYPES = [\n  'valid.one',\n  UNQUOTED_EVENT,\n] as const;\n"},
		{"label": "numeric literal", "src": "export const ENGINE_EVENT_TYPES = [\n  'valid.one',\n  42,\n] as const;\n"},
		{"label": "template literal", "src": "export const ENGINE_EVENT_TYPES = [\n  'valid.one',\n  `tmpl.event`,\n] as const;\n"},
		{"label": "unterminated quote", "src": "export const ENGINE_EVENT_TYPES = [\n  'valid.one',\n  'broken\n] as const;\n"},
		{"label": "missing comma", "src": "export const ENGINE_EVENT_TYPES = [\n  'valid.one'\n  'valid.two',\n] as const;\n"},
	]:
		var res := parse_engine_event_types_source(String(bad_case["src"]))
		var rerrs: Array = res.get("errors", []) as Array
		t.is_false(bool(res.get("ok", true)),
			"RED: parser fails on unparsed %s entry instead of skipping" % String(bad_case["label"]))
		t.is_true(rerrs.size() > 0,
			"RED: parser reports diagnostic error for %s" % String(bad_case["label"]))


static func parse_engine_event_types_source(text: String) -> Dictionary:
	var out: Array[String] = []
	var errors: Array[String] = []
	var sym_idx := text.find("ENGINE_EVENT_TYPES")
	if sym_idx < 0:
		errors.append("ENGINE_EVENT_TYPES declaration not found")
		return {"ok": false, "types": out, "errors": errors}
	var eq_idx := text.find("=", sym_idx + "ENGINE_EVENT_TYPES".length())
	if eq_idx < 0:
		errors.append("ENGINE_EVENT_TYPES initializer '=' not found")
		return {"ok": false, "types": out, "errors": errors}
	var open_idx := text.find("[", eq_idx + 1)
	if open_idx < 0:
		errors.append("ENGINE_EVENT_TYPES opening '[' not found")
		return {"ok": false, "types": out, "errors": errors}

	var i := open_idx + 1
	var n := text.length()
	var line_no := 1 + text.substr(0, i).count("\n")
	var expect_value := true
	var closed := false

	while i < n:
		var ch := text[i]
		if ch == "\n":
			line_no += 1
			i += 1
			continue
		if ch == " " or ch == "\t" or ch == "\r":
			i += 1
			continue
		if ch == "/" and i + 1 < n and text[i + 1] == "/":
			i += 2
			while i < n and text[i] != "\n":
				i += 1
			continue
		if ch == "/" and i + 1 < n and text[i + 1] == "*":
			var close_c := text.find("*/", i + 2)
			if close_c < 0:
				errors.append("unterminated block comment in ENGINE_EVENT_TYPES at line %d" % line_no)
				return {"ok": false, "types": out, "errors": errors}
			line_no += text.substr(i, close_c + 2 - i).count("\n")
			i = close_c + 2
			continue
		if ch == "]":
			closed = true
			break
		if ch == ",":
			if expect_value:
				errors.append("unexpected ',' before entry at line %d" % line_no)
				return {"ok": false, "types": out, "errors": errors}
			expect_value = true
			i += 1
			continue
		if ch == "'" or ch == "\"":
			if not expect_value:
				errors.append("missing ',' before string literal at line %d" % line_no)
				return {"ok": false, "types": out, "errors": errors}
			var quote := ch
			i += 1
			var val := ""
			var terminated := false
			while i < n:
				var c := text[i]
				if c == "\n" or c == "\r":
					break
				if c == "\\":
					if i + 1 >= n:
						break
					var esc := text[i + 1]
					match esc:
						"n": val += "\n"
						"r": val += "\r"
						"t": val += "\t"
						_: val += esc
					i += 2
					continue
				if c == quote:
					terminated = true
					i += 1
					break
				val += c
				i += 1
			if not terminated:
				errors.append("unterminated string literal starting at line %d" % line_no)
				return {"ok": false, "types": out, "errors": errors}
			if val.is_empty():
				errors.append("empty event type string literal at line %d" % line_no)
				return {"ok": false, "types": out, "errors": errors}
			out.append(val)
			expect_value = false
			continue

		var line_end := text.find("\n", i)
		var snippet := (text.substr(i, line_end - i) if line_end >= 0 else text.substr(i)).strip_edges()
		if snippet.length() > 40:
			snippet = snippet.substr(0, 40)
		errors.append("unparsed entry in ENGINE_EVENT_TYPES at line %d: '%s'" % [line_no, snippet])
		return {"ok": false, "types": out, "errors": errors}

	if not closed:
		errors.append("unterminated ENGINE_EVENT_TYPES array (missing closing ']')")
	if out.is_empty():
		errors.append("ENGINE_EVENT_TYPES array is empty")
	return {"ok": errors.is_empty(), "types": out, "errors": errors}


func _load_runtime_engine_event_types(t: RefCounted, engine_dir: String) -> Array[String]:
	var js_path := engine_dir + "/packages/core/dist/event-vocabulary.js"
	t.is_true(FileAccess.file_exists(js_path),
		"pinned compiled engine event vocabulary exists (%s)" % js_path)
	if not FileAccess.file_exists(js_path):
		return []
	var tmp_path := ProjectSettings.globalize_path("user://engine_event_types_check_%d.json" % OS.get_process_id()).replace("\\", "/")
	var js_url_arg := js_path.replace("\\", "/")
	var node_code := "import { pathToFileURL } from 'node:url'; import fs from 'node:fs'; const m = await import(pathToFileURL(process.argv[1]).href); fs.writeFileSync(process.argv[2], JSON.stringify(m.ENGINE_EVENT_TYPES));"
	var out_buf: Array = []
	var exit_code := OS.execute("node", ["--input-type=module", "-e", node_code, js_url_arg, tmp_path], out_buf, true)
	t.equals(exit_code, 0, "node exported live ENGINE_EVENT_TYPES cleanly")
	if exit_code != 0 or not FileAccess.file_exists(tmp_path):
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)
		return []
	var raw_json := FileAccess.get_file_as_string(tmp_path)
	DirAccess.remove_absolute(tmp_path)
	var parsed_v: Variant = JSON.parse_string(raw_json)
	t.check(parsed_v is Array, "exported ENGINE_EVENT_TYPES JSON parsed as Array")
	var exported: Array[String] = []
	if parsed_v is Array:
		for item: Variant in (parsed_v as Array):
			exported.append(String(item))
	return exported


func _replay_handled_events(_t: RefCounted, tree: SceneTree, events: Array) -> Dictionary:
	var results: Dictionary = {}
	var bus := EventBus.new()
	var client := NetworkClient.new()
	client.bus = bus
	var d := Diorama.new()
	tree.root.add_child(bus)
	tree.root.add_child(client)
	tree.root.add_child(d)
	await tree.process_frame
	d.call("build")

	var session := Session.new()
	tree.root.add_child(session)
	session.call("setup", d, client, bus)

	var iso: Node = d.get("iso")
	var player: Node = d.get("player")
	var rig: Node = d.get("rig")

	for ev_v: Variant in events:
		if not (ev_v is Dictionary):
			continue
		var ev := ev_v as Dictionary
		var ev_type := String(ev.get("type", ""))
		var tx_before := (session.get("transcript") as Array).size()
		var zone_before := String(session.call("player_zone"))
		var parent_before: Node = player.get_parent() if player != null else null
		var iso_zone_before := String(iso.call("player_zone")) if (iso != null and iso.has_method("player_zone")) else ""
		var actors_before := iso.get_node("Actors").get_child_count() if (iso != null and iso.has_node("Actors")) else 0
		var dim_before := bool(rig.call("is_dim")) if rig != null else false

		await session.call("_present", ev)

		var tx_after: Array = session.get("transcript") as Array
		var bespoke_added := 0
		for i in range(tx_before, tx_after.size()):
			if not String(tx_after[i]).contains(Session.FALLBACK_TAG):
				bespoke_added += 1

		var parent_after: Node = player.get_parent() if player != null else null
		var iso_zone_after := String(iso.call("player_zone")) if (iso != null and iso.has_method("player_zone")) else ""
		var actors_after := iso.get_node("Actors").get_child_count() if (iso != null and iso.has_node("Actors")) else 0
		var dim_after := bool(rig.call("is_dim")) if rig != null else false
		var scene_changed := (
			String(session.call("player_zone")) != zone_before
			or parent_after != parent_before
			or iso_zone_after != iso_zone_before
			or actors_after != actors_before
			or dim_after != dim_before
		)
		results[ev_type] = {
			"bespoke_transcript_lines": bespoke_added,
			"scene_changed": scene_changed,
		}

	session.queue_free()
	d.queue_free()
	client.queue_free()
	bus.queue_free()
	await tree.process_frame
	return results


static func validate_manifest(
	engine_types: Array[String],
	manifest: Dictionary,
	today_iso: String,
	replay_results: Dictionary,
) -> Array[String]:
	var errors: Array[String] = []
	var engine_set: Dictionary = {}
	for et: String in engine_types:
		engine_set[et] = true
		if not manifest.has(et):
			errors.append("missing engine event type: %s" % et)

	for mt_v: Variant in manifest.keys():
		var mt := String(mt_v)
		if not engine_set.has(mt):
			errors.append("manifest event type not in engine list: %s" % mt)
			continue
		var entry_v: Variant = manifest[mt]
		if not (entry_v is Dictionary):
			errors.append("manifest entry must be an object: %s" % mt)
			continue
		var entry := entry_v as Dictionary
		var status := String(entry.get("status", ""))
		match status:
			"handled":
				if not Session.RENDERED.has(mt):
					errors.append("handled event type is not in Session.RENDERED: %s" % mt)
				elif not replay_results.has(mt):
					errors.append("handled event type missing replay fixture entry: %s" % mt)
				else:
					var res: Dictionary = replay_results[mt] as Dictionary
					if int(res.get("bespoke_transcript_lines", 0)) <= 0 and not bool(res.get("scene_changed", false)):
						errors.append("handled event type changed nothing on replay: %s" % mt)
			"no-visible-effect":
				if String(entry.get("reason", "")).strip_edges().is_empty():
					errors.append("no-visible-effect missing reason: %s" % mt)
			"todo":
				if String(entry.get("owner", "")).strip_edges().is_empty():
					errors.append("todo missing owner: %s" % mt)
				var expiry := String(entry.get("expiry", "")).strip_edges()
				if not _is_valid_iso_date(expiry):
					errors.append("todo invalid expiry '%s': %s" % [expiry, mt])
				elif today_iso > expiry:
					errors.append("expired todo entry: %s (expiry %s < %s)" % [mt, expiry, today_iso])
			_:
				errors.append("unknown manifest status '%s' on %s" % [status, mt])
	return errors


static func _is_valid_iso_date(s: String) -> bool:
	if s.length() != 10:
		return false
	if s[4] != "-" or s[7] != "-":
		return false
	var parts := s.split("-")
	return parts.size() == 3 and parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2].is_valid_int()

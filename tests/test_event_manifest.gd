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
	var in_array := false
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile("'([^']+)'")
	for raw: String in text.split("\n", false):
		var stripped := raw.strip_edges()
		if not in_array:
			if stripped.contains("ENGINE_EVENT_TYPES") and stripped.contains("["):
				in_array = true
			continue
		if stripped.begins_with("//"):
			continue
		if stripped.begins_with("]"):
			break
		var m := re.search(stripped)
		if m != null:
			out.append(m.get_string(1))

	t.check(out.size() >= 165, "read dynamic ENGINE_EVENT_TYPES list from pinned engine checkout",
		"got %d" % out.size())
	return out


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

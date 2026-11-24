## test_profile_policy.gd — unresolved aiProfile policy (`fail` in debug/CI, `warn` in release).
extends RefCounted

const Harness := preload("res://tools/sidecar_harness.gd")
const NetworkClient := preload("res://client/network_client.gd")
const EventBus := preload("res://client/event_bus.gd")
const Diorama := preload("res://stage/diorama.gd")
const Session := preload("res://stage/session.gd")

const HOST_PACK := "chapel-threshold"
const SEED := 71
const UNKNOWN_PROFILE := "nonexistent_stage_test_profile"


func run_async(t: RefCounted) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		t.check(false, "SceneTree available", "wire tests require process frames")
		return

	await _test_debug_default_and_salt_road_clean(t, tree)

	var doctored_pack := _write_unknown_profile_pack()
	t.is_false(doctored_pack.is_empty(), "created doctored content pack with unknown profile")
	if doctored_pack.is_empty():
		return

	await _test_fail_mode_refuses_unknown_profile(t, tree, doctored_pack)
	await _test_warn_mode_surfaces_warning_to_transcript(t, tree, doctored_pack)

	if FileAccess.file_exists(doctored_pack):
		DirAccess.remove_absolute(doctored_pack)


func _test_debug_default_and_salt_road_clean(t: RefCounted, tree: SceneTree) -> void:
	var harness: RefCounted = Harness.new()
	if OS.is_debug_build():
		t.equals(String(harness.call("effective_unresolved_profile_mode")), "fail",
			"debug builds default to --unresolved-ai-profile fail")
	else:
		t.equals(String(harness.call("effective_unresolved_profile_mode")), "warn",
			"release exports default to --unresolved-ai-profile warn")

	var extra: Array[String] = [
		"--content", Harness.salt_road_pack(),
		"--manifest", Harness.salt_road_manifest(),
		"--start", Diorama.PLAYER_START_ZONE,
	]
	harness.extra_args = extra
	var started: bool = await harness.call("start", HOST_PACK, SEED)
	t.is_true(started, "Salt Road loads cleanly under debug/CI fail policy")
	var stderr := String(harness.call("stderr_text"))
	t.is_false(stderr.contains("UNRESOLVED_AI_PROFILE"),
		"Salt Road produces no unresolved-profile warnings")
	t.is_false(stderr.contains("aiProfile"),
		"Salt Road drops no profile fields")
	harness.call("stop")
	await tree.create_timer(0.3).timeout


func _test_fail_mode_refuses_unknown_profile(t: RefCounted, tree: SceneTree, pack_path: String) -> void:
	var harness: RefCounted = Harness.new()
	harness.set("forward_stderr", false)
	harness.set("unresolved_ai_profile_override", "fail")
	var extra: Array[String] = [
		"--content", pack_path,
		"--manifest", Harness.salt_road_manifest(),
		"--start", Diorama.PLAYER_START_ZONE,
	]
	harness.extra_args = extra

	var started: bool = await harness.call("start", HOST_PACK, SEED)
	t.is_false(started, "fail mode refuses pack containing unknown profile")
	var fail_msg := String(harness.get("failure"))
	var stderr := String(harness.call("stderr_text"))
	t.contains(stderr, "SIDECAR_CONTENT_REFUSED", "sidecar stderr reports content refusal code")
	t.contains(stderr, UNKNOWN_PROFILE, "sidecar stderr names the unresolved profile")
	t.contains(fail_msg, UNKNOWN_PROFILE, "harness failure exposes unresolved profile refusal")

	var d := Diorama.new()
	tree.root.add_child(d)
	await tree.process_frame
	d.call("build")
	var bus := EventBus.new()
	var client := NetworkClient.new()
	client.bus = bus
	var session := Session.new()
	tree.root.add_child(bus)
	tree.root.add_child(client)
	tree.root.add_child(session)
	session.call("setup", d, client, bus)
	session.call("report_startup_refusal", fail_msg)

	var found_tx := false
	for line: Variant in (session.get("transcript") as Array):
		if String(line).contains("Sidecar refused pack:") and String(line).contains(UNKNOWN_PROFILE):
			found_tx = true
	t.is_true(found_tx, "refusal error reaches screen transcript visibly")

	harness.call("stop")
	session.queue_free()
	d.queue_free()
	client.queue_free()
	bus.queue_free()
	await tree.create_timer(0.3).timeout


func _test_warn_mode_surfaces_warning_to_transcript(t: RefCounted, tree: SceneTree, pack_path: String) -> void:
	var harness: RefCounted = Harness.new()
	harness.set("forward_stderr", false)
	harness.set("unresolved_ai_profile_override", "warn")
	var extra: Array[String] = [
		"--content", pack_path,
		"--manifest", Harness.salt_road_manifest(),
		"--start", Diorama.PLAYER_START_ZONE,
	]
	harness.extra_args = extra

	var started: bool = await harness.call("start", HOST_PACK, SEED)
	t.is_true(started, "release/warn mode allows pack with unknown profile to boot")
	if not started:
		harness.call("stop")
		return

	var stderr := String(harness.call("stderr_text"))
	t.contains(stderr, "[sidecar] warning", "warn mode emits sidecar warning line on stderr")
	t.contains(stderr, "UNRESOLVED_AI_PROFILE", "stderr warning carries unresolved-profile code")
	t.contains(stderr, UNKNOWN_PROFILE, "stderr warning names offending profile")

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

	var handshake: Dictionary = await client.call("attach", Harness.HOST, int(harness.get("port")), "stage/test-warn", "0.1.0")
	t.is_false(handshake.is_empty(), "stage attaches cleanly in warn mode")
	var stderr_count := int(session.call("ingest_sidecar_stderr", stderr))
	var dedup_count := int(session.call("ingest_pack_intake", handshake))
	t.check(stderr_count >= 1, "ingest_sidecar_stderr surfaces warning lines", "got %d" % stderr_count)
	t.equals(dedup_count, 0, "ingest_pack_intake deduplicates warnings already surfaced from stderr")

	var on_screen := false
	for line: Variant in (session.get("transcript") as Array):
		var s := String(line)
		if s.contains("[fallback]") and s.contains("[color=") and s.contains(UNKNOWN_PROFILE):
			on_screen = true
	t.is_true(on_screen, "warning renders on screen in fallback style inside session.transcript")

	var in_log := false
	for dline: Variant in (session.get("diagnostics") as Array):
		if String(dline).contains("[warning]") and String(dline).contains(UNKNOWN_PROFILE):
			in_log = true
	t.is_true(in_log, "warning is also recorded in session.diagnostics")

	var Playable := preload("res://stage/playable.gd")
	var standalone := Session.new()
	var d_only := Diorama.new()
	var b_only := EventBus.new()
	var c_only := NetworkClient.new()
	c_only.bus = b_only
	tree.root.add_child(b_only)
	tree.root.add_child(c_only)
	tree.root.add_child(d_only)
	await tree.process_frame
	d_only.call("build")
	tree.root.add_child(standalone)
	standalone.call("setup", d_only, c_only, b_only)
	var intake_count := int(standalone.call("ingest_pack_intake", handshake))
	t.check(intake_count >= 1, "ingest_pack_intake surfaces packIntake.warnings when stderr was not pre-ingested")
	var intake_fallback := false
	for l: Variant in (standalone.get("transcript") as Array):
		if String(l).contains("[fallback]") and String(l).contains(UNKNOWN_PROFILE):
			intake_fallback = true
	t.is_true(intake_fallback, "packIntake fallback warning reaches transcript cleanly")
	standalone.queue_free()
	d_only.queue_free()
	c_only.queue_free()
	b_only.queue_free()

	# Also prove Playable._drain_sidecar_stderr() reads warning file onto HUD _log/_toast.
	var d_hud := Diorama.new()
	tree.root.add_child(d_hud)
	await tree.process_frame
	var hud := Playable.new()
	d_hud.add_child(hud)
	var hb := EventBus.new()
	var hc := NetworkClient.new()
	hc.bus = hb
	var hs := Session.new()
	d_hud.add_child(hb)
	d_hud.add_child(hc)
	d_hud.add_child(hs)
	hs.call("setup", d_hud, hc, hb)
	hs.narrated.connect(Callable(hud, "_say"))
	hud.set("session", hs)
	var warn_file := OS.get_user_data_dir().path_join("hud_warn_%d.log" % Time.get_ticks_usec())
	var wf := FileAccess.open(warn_file, FileAccess.WRITE)
	wf.store_string("[sidecar] warning [UNRESOLVED_AI_PROFILE] entities[0].aiProfile: %s\n" % UNKNOWN_PROFILE)
	wf.close()
	hud.set("_sidecar_stderr_path", warn_file)
	hud.call("_drain_sidecar_stderr")
	t.contains((hud.get("_log") as RichTextLabel).text, "[fallback]", "HUD log displays drained stderr warning in fallback style")
	t.contains((hud.get("_log") as RichTextLabel).text, UNKNOWN_PROFILE, "HUD log displays profile id from drained stderr")
	if FileAccess.file_exists(warn_file):
		DirAccess.remove_absolute(warn_file)
	hud.queue_free()
	d_hud.queue_free()

	client.call("detach")
	session.queue_free()
	d.queue_free()
	client.queue_free()
	bus.queue_free()
	harness.call("stop")
	await tree.create_timer(0.4).timeout


func _write_unknown_profile_pack() -> String:
	var src_path := Harness.salt_road_pack()
	if not FileAccess.file_exists(src_path):
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(src_path))
	if not (parsed is Dictionary):
		return ""
	var pack := (parsed as Dictionary).duplicate(true)
	var entities: Array = (pack.get("entities", []) as Array).duplicate(true)
	entities.append({
		"id": "npc-unresolved-probe",
		"name": "Dock Inspector Probe",
		"type": "npc",
		"aiProfile": UNKNOWN_PROFILE,
	})
	pack["entities"] = entities
	var placements: Array = (pack.get("placements", []) as Array).duplicate(true)
	placements.append({
		"entityId": "npc-unresolved-probe",
		"zoneId": "counting-house",
	})
	pack["placements"] = placements
	var out_path := OS.get_user_data_dir().path_join("doctored_unknown_profile_%d.json" % Time.get_ticks_usec())
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(pack))
	f.close()
	return out_path

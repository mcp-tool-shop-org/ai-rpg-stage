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
	_test_incremental_stderr_drain(t)
	_test_play_mjs_release_handoff(t, doctored_pack)

	if FileAccess.file_exists(doctored_pack):
		DirAccess.remove_absolute(doctored_pack)


func _test_debug_default_and_salt_road_clean(t: RefCounted, tree: SceneTree) -> void:
	t.equals(Harness.choose_unresolved_profile_mode(true, ""), "fail",
		"mode chooser selects fail when OS.is_debug_build() is true")
	t.equals(Harness.choose_unresolved_profile_mode(false, ""), "warn",
		"mode chooser selects warn when OS.is_debug_build() is false")
	t.equals(Harness.choose_unresolved_profile_mode(true, "warn"), "warn",
		"mode chooser respects explicit warn override in debug build")
	t.equals(Harness.choose_unresolved_profile_mode(false, "fail"), "fail",
		"mode chooser respects explicit fail override in release build")

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
	var warn_file := OS.get_user_data_dir().path_join("hud_warn_%d_%d.log" % [OS.get_process_id(), Time.get_ticks_usec()])
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
	var out_path := OS.get_user_data_dir().path_join("doctored_unknown_profile_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(pack))
	f.close()
	return out_path


func _test_incremental_stderr_drain(t: RefCounted) -> void:
	var Playable := preload("res://stage/playable.gd")
	var tree := Engine.get_main_loop() as SceneTree
	var d := Diorama.new()
	tree.root.add_child(d)
	var hud := Playable.new()
	d.add_child(hud)
	var b := EventBus.new()
	var c := NetworkClient.new()
	c.bus = b
	var s := Session.new()
	d.add_child(b)
	d.add_child(c)
	d.add_child(s)
	s.call("setup", d, c, b)
	hud.set("session", s)

	var log_path := OS.get_user_data_dir().path_join("inc_stderr_%d_%d.log" % [OS.get_process_id(), Time.get_ticks_usec()])
	var line1 := "[sidecar] warning [UNRESOLVED_AI_PROFILE] entities[0].aiProfile: first_prof_probe\n"
	var w1 := FileAccess.open(log_path, FileAccess.WRITE)
	w1.store_string(line1)
	w1.close()
	var n1 := line1.to_utf8_buffer().size()

	hud.set("_sidecar_stderr_path", log_path)
	hud.call("_drain_sidecar_stderr")
	t.equals(int(hud.call("sidecar_stderr_offset")), n1, "first incremental drain advances byte offset to %d" % n1)
	t.equals((s.get("diagnostics") as Array).size(), 1, "first incremental drain ingests first warning")

	# Overwrite bytes 0..n1 with an equal-length distinct probe line (file size unchanged):
	# incremental seek must NOT re-read bytes 0..n1.
	var probe_same_len := "[sidecar] warning [UNRESOLVED_AI_PROFILE] entities[0].aiProfile: stale_re_read!!!\n"
	t.equals(probe_same_len.to_utf8_buffer().size(), n1, "probe line matches first-chunk byte length cleanly")
	var rw := FileAccess.open(log_path, FileAccess.READ_WRITE)
	rw.seek(0)
	rw.store_string(probe_same_len)
	rw.close()
	hud.call("_drain_sidecar_stderr")
	t.equals((s.get("diagnostics") as Array).size(), 1, "unchanged length after overwrite skips already-read bytes")

	# Append a second warning line past offset n1: only bytes n1..n1+n2 are read and ingested.
	var line2 := "[sidecar] warning [UNRESOLVED_AI_PROFILE] entities[1].aiProfile: second_prof_probe\n"
	var n2 := line2.to_utf8_buffer().size()
	var rw2 := FileAccess.open(log_path, FileAccess.READ_WRITE)
	rw2.seek(n1)
	rw2.store_string(line2)
	rw2.close()
	hud.call("_drain_sidecar_stderr")
	t.equals(int(hud.call("sidecar_stderr_offset")), n1 + n2, "second incremental drain advances byte offset cleanly")
	t.equals((s.get("diagnostics") as Array).size(), 2, "incremental drain ingests appended second warning only")
	var diag_all := "\n".join(PackedStringArray(s.get("diagnostics") as Array))
	t.is_false(diag_all.contains("stale_re_read!!!"), "incremental drain never re-reads earlier bytes before offset")
	t.contains(diag_all, "second_prof_probe", "incremental drain ingests appended warning past offset")

	if FileAccess.file_exists(log_path):
		DirAccess.remove_absolute(log_path)
	hud.queue_free()
	d.queue_free()


func _test_play_mjs_release_handoff(t: RefCounted, doctored_pack: String) -> void:
	var project_dir := ProjectSettings.globalize_path("res://").rstrip("/")
	var engine_dir := Harness.find_engine_dir()
	if not FileAccess.file_exists(Harness.bin_path(engine_dir)):
		t.check(false, "engine CLI built for play.mjs hand-off test", Harness.bin_path(engine_dir))
		return

	var pid := OS.get_process_id()
	var stamp := Time.get_ticks_usec()
	var base_tmp := OS.get_user_data_dir().path_join("play_handoff_%d_%d" % [pid, stamp]).replace("\\", "/")
	var fake_forge := base_tmp + "/forge"
	var forge_pack_dir := fake_forge + "/dogfood/output/salt-road"
	DirAccess.make_dir_recursive_absolute(forge_pack_dir)
	var pack_bytes := FileAccess.get_file_as_bytes(doctored_pack)
	var pf := FileAccess.open(forge_pack_dir + "/pack.json", FileAccess.WRITE)
	pf.store_buffer(pack_bytes)
	pf.close()

	var invalid_res_path := base_tmp + "/invalid_mode.json"
	var fail_res_path := base_tmp + "/default_fail.json"
	var rel_res_path := base_tmp + "/release_warn.json"
	var sync_dump_path := base_tmp + "/stage_summary.json"
	var godot_bin := OS.get_executable_path()
	var play_js := project_dir + "/tools/play.mjs"

	var node_runner := (
		"import { spawnSync } from 'node:child_process';"
		+ "import fs from 'node:fs';"
		+ "const [, mode, playJs, outJson, ...extra] = process.argv;"
		+ "const r = spawnSync(process.execPath, [playJs, ...extra], { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 25000 });"
		+ "fs.writeFileSync(outJson, JSON.stringify({ mode, status: r.status, stdout: r.stdout || '', stderr: r.stderr || '', error: r.error ? r.error.message : '' }));"
	)

	# 1. Invalid mode rejected (single validation block in play.mjs).
	var o1: Array = []
	var ec1 := OS.execute("node", [
		"--input-type=module", "-e", node_runner, "invalid", play_js, invalid_res_path,
		"--engine", engine_dir, "--forge", fake_forge, "--unresolved-ai-profile", "invalid",
	], o1, true)
	t.equals(ec1, 0, "invalid-mode runner finished")
	var inv_raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(invalid_res_path)) if FileAccess.file_exists(invalid_res_path) else null
	t.is_true(inv_raw is Dictionary, "invalid-mode result JSON parsed")
	var inv_doc: Dictionary = inv_raw if inv_raw is Dictionary else {}
	t.equals(int(inv_doc.get("status", -1)), 1, "play.mjs rejects invalid --unresolved-ai-profile value with exit 1")
	t.contains(String(inv_doc.get("stderr", "")), "invalid --unresolved-ai-profile", "play.mjs invalid mode names flag")

	# 2. Default mode (fail) refuses unknown-profile pack before opening Godot.
	var o2: Array = []
	var ec2 := OS.execute("node", [
		"--input-type=module", "-e", node_runner, "default_fail", play_js, fail_res_path,
		"--port", "0", "--engine", engine_dir, "--forge", fake_forge, "--godot", godot_bin, "--stage-headless", "--quit-after-sync", sync_dump_path,
	], o2, true)
	t.equals(ec2, 0, "default-fail runner finished")
	var fail_raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(fail_res_path)) if FileAccess.file_exists(fail_res_path) else null
	t.is_true(fail_raw is Dictionary, "default-fail result JSON parsed")
	var fail_doc: Dictionary = fail_raw if fail_raw is Dictionary else {}
	t.equals(int(fail_doc.get("status", -1)), 1, "play.mjs default (fail) exits 1 when unknown profile pack fails load gate")
	t.contains(String(fail_doc.get("stderr", "")), UNKNOWN_PROFILE, "play.mjs fail refusal names offending profile")

	# 3. `--release` selects warn, spawns sidecar + headless stage, hands off --sidecar-stderr,
	#    and surfaces the warning to HUD log, session.transcript, and session.diagnostics.
	var o3: Array = []
	var ec3 := OS.execute("node", [
		"--input-type=module", "-e", node_runner, "release_warn", play_js, rel_res_path,
		"--release", "--port", "0", "--engine", engine_dir, "--forge", fake_forge, "--godot", godot_bin, "--stage-headless", "--quit-after-sync", sync_dump_path,
	], o3, true)
	t.equals(ec3, 0, "release-handoff runner finished")
	var rel_raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(rel_res_path)) if FileAccess.file_exists(rel_res_path) else null
	t.is_true(rel_raw is Dictionary, "release-handoff result JSON parsed")
	var rel_doc: Dictionary = rel_raw if rel_raw is Dictionary else {}
	t.equals(int(rel_doc.get("status", -1)), 0, "play.mjs --release exits 0 after synced stage exits")
	var rel_stdout := String(rel_doc.get("stdout", ""))
	t.contains(rel_stdout, "warn", "play.mjs --release forwards warn mode CLI args")
	t.contains(rel_stdout, UNKNOWN_PROFILE, "play.mjs --release forwards unresolved profile warning to launcher output")

	t.is_true(FileAccess.file_exists(sync_dump_path), "headless Playable wrote quit-after-sync summary")
	if FileAccess.file_exists(sync_dump_path):
		var sync_raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(sync_dump_path))
		t.is_true(sync_raw is Dictionary, "quit-after-sync summary JSON parsed")
		var sync_doc: Dictionary = sync_raw if sync_raw is Dictionary else {}
		t.contains(String(sync_doc.get("status", "")), "attached", "Playable attached cleanly under play.mjs --release")
		t.contains(String(sync_doc.get("log", "")), "[fallback]", "HUD log received fallback-styled warning from play.mjs --sidecar-stderr")
		t.contains(String(sync_doc.get("log", "")), UNKNOWN_PROFILE, "HUD log shows unresolved profile name from play.mjs --release")
		var tx_joined := "\n".join(PackedStringArray(sync_doc.get("transcript", []) as Array))
		var diag_joined := "\n".join(PackedStringArray(sync_doc.get("diagnostics", []) as Array))
		t.is_true(bool(sync_doc.get("has_sidecar_stderr_path", false)), "Playable received --sidecar-stderr path from play.mjs")
		t.check(int(sync_doc.get("sidecar_stderr_offset", 0)) > 0, "Playable drained non-empty sidecar stderr log from play.mjs", "offset=%s" % str(sync_doc.get("sidecar_stderr_offset", 0)))
		t.contains(tx_joined, UNKNOWN_PROFILE, "session.transcript contains handed-off profile warning")
		t.contains(diag_joined, "[warning]", "session.diagnostics records handed-off warning")

	# Clean up temp artifacts under user://.
	for tmp_file: String in [forge_pack_dir + "/pack.json", invalid_res_path, fail_res_path, rel_res_path, sync_dump_path]:
		if FileAccess.file_exists(tmp_file):
			DirAccess.remove_absolute(tmp_file)
	for tmp_dir: String in [forge_pack_dir, fake_forge + "/dogfood/output", fake_forge + "/dogfood", fake_forge, base_tmp]:
		if DirAccess.dir_exists_absolute(tmp_dir):
			DirAccess.remove_absolute(tmp_dir)

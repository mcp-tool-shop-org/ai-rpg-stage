## sidecar_harness.gd — start a real sidecar, from inside Godot.
##
## The wire tests drive the ACTUAL engine. A mock would prove that the stage agrees
## with a mock, which is the failure mode the studio has a memory file about: a
## producer's own tests cannot answer "does anything real call this."
##
## Why a fixed port instead of the sidecar's ephemeral one: learning an ephemeral
## port means reading the child's stderr, and GDScript's subprocess pipes are the
## documented-buggy surface this whole transport exists to avoid (godot#102340). So
## the harness picks the port and the sidecar is told to use it. If a port is in use,
## the next candidate is tried — a stale sidecar from an interrupted run is a normal
## thing to walk into, not a reason to fail the suite.
extends RefCounted

const HOST := "127.0.0.1"

## High, unregistered, and unlikely to collide with anything the studio runs.
const CANDIDATE_PORTS := [47821, 47822, 47823, 47824]

var pid := -1
var port := 0
var engine_dir := ""
var failure := ""
var stderr_file_path := ""
var _last_stderr := ""

## Override `--unresolved-ai-profile` (`"fail"` or `"warn"`). Empty chooses by build
## type: `"fail"` when `OS.is_debug_build()` is true (debug/CI), `"warn"` in release exports.
var unresolved_ai_profile_override := ""

## Forward child sidecar stderr to this process's stderr (default true). Negative tests
## that intentionally trigger warnings or refusals set this false while still reading
## `stderr_text()` directly from the captured sidecar stderr log.
var forward_stderr := true


## Resolve the engine checkout. Env var first, then a sibling directory.
##
## No rig-specific absolute path: this repo is public and a hard-coded absolute drive path
## would be both wrong for everyone else and quietly wrong here the day it moves.
static func find_engine_dir() -> String:
	var from_env := OS.get_environment("AI_RPG_ENGINE_DIR")
	if not from_env.is_empty():
		return from_env.replace("\\", "/")
	# `res://` may be inside a pck, so resolve through the actual filesystem path.
	var project_dir := ProjectSettings.globalize_path("res://").rstrip("/")
	return project_dir.get_base_dir() + "/ai-rpg-engine"


static func bin_path(dir: String) -> String:
	return dir + "/packages/cli/dist/bin.js"


## The exported Salt Road pack the sidecar loads with `--content`.
##
## Lives in world-forge's output, a SIBLING of the engine checkout — the same layout the
## engine itself is resolved by, so CI and a developer's machine agree.
static func salt_road_pack() -> String:
	var from_env := OS.get_environment("SALT_ROAD_PACK")
	if not from_env.is_empty():
		return from_env.replace("\\", "/")
	var engine_dir := find_engine_dir()
	return engine_dir.get_base_dir() + "/world-forge/dogfood/output/salt-road/pack.json"


## Sibling of the stage fixtures. The sidecar load gate refuses --content
## without --manifest (SIDECAR_MANIFEST_REQUIRED).
static func salt_road_manifest() -> String:
	var from_env := OS.get_environment("SALT_ROAD_MANIFEST")
	if not from_env.is_empty():
		return from_env.replace("\\", "/")
	var project_dir := ProjectSettings.globalize_path("res://").rstrip("/")
	return project_dir + "/fixtures/salt-road.manifest.json"


## Extra sidecar arguments — content, start zone, scenario cue. Set before `start`.
##
## Kept as a plain array rather than typed fields so the harness does not have to grow a
## parameter every time the command does; the COMMAND owns its own validation and says so
## clearly on stderr, which is where a bad value should surface.
var extra_args: Array[String] = []


## Policy mode passed via `--unresolved-ai-profile`: `fail` in debug builds and CI,
## `warn` in release exports (unless `unresolved_ai_profile_override` is set).
func effective_unresolved_profile_mode() -> String:
	if not unresolved_ai_profile_override.is_empty():
		return unresolved_ai_profile_override
	return "fail" if OS.is_debug_build() else "warn"


func stderr_text() -> String:
	if not stderr_file_path.is_empty() and FileAccess.file_exists(stderr_file_path):
		_last_stderr = FileAccess.get_file_as_string(stderr_file_path)
	return _last_stderr


func stderr_lines() -> PackedStringArray:
	return stderr_text().split("\n", false)


func cleanup_stderr_file() -> void:
	if not stderr_file_path.is_empty() and FileAccess.file_exists(stderr_file_path):
		DirAccess.remove_absolute(stderr_file_path)
		stderr_file_path = ""


## Spawn `node bin.js sidecar <pack> --seed <n> --listen <port> --unresolved-ai-profile <mode>` plus `extra_args`.
## Returns true on success; `failure` explains any false.
func start(pack_id: String, seed: int) -> bool:
	cleanup_stderr_file()
	_last_stderr = ""
	engine_dir = find_engine_dir()
	var bin := bin_path(engine_dir)

	if not FileAccess.file_exists(bin):
		failure = (
			"engine CLI not built at %s. The wire tests drive the real sim, so this is a hard "
			+ "failure rather than a skip — a silently skipped wire proof is the vacuous green "
			+ "this suite refuses elsewhere. Set AI_RPG_ENGINE_DIR, or run `npm ci && npm run build` "
			+ "in the engine checkout."
		) % bin
		return false

	var project_dir := ProjectSettings.globalize_path("res://").rstrip("/")
	var spawn_script := project_dir + "/tools/sidecar_spawn.mjs"
	var profile_mode := effective_unresolved_profile_mode()

	for candidate: int in CANDIDATE_PORTS:
		stderr_file_path = OS.get_user_data_dir().path_join("sidecar_%d_%d.stderr.log" % [Time.get_ticks_usec(), candidate])
		var args: Array = [
			spawn_script,
			stderr_file_path,
			"1" if forward_stderr else "0",
			bin,
			"sidecar",
			pack_id,
			"--seed",
			str(seed),
			"--listen",
			str(candidate),
			"--unresolved-ai-profile",
			profile_mode,
		]
		args.append_array(extra_args)
		var spawned := OS.create_process("node", args, false)
		if spawned <= 0:
			failure = "OS.create_process('node') failed — is node on PATH?"
			return false

		var exited_early := false
		var outcome := await _wait_until_listening(candidate, spawned)
		if outcome == 1:
			pid = spawned
			port = candidate
			return true
		if outcome == -1:
			exited_early = true

		# That port did not come up. Reap before trying the next one, so a failed
		# attempt cannot leave a process holding a port for the rest of the suite.
		if OS.is_process_running(spawned):
			OS.kill(spawned)
		await _sleep_ms(120)
		var captured := stderr_text().strip_edges()
		if exited_early and not captured.contains("EADDRINUSE"):
			failure = "sidecar exited before listening (mode=%s): %s" % [profile_mode, captured]
			return false

	failure = "no candidate port came up: %s%s" % [
		str(CANDIDATE_PORTS),
		"" if stderr_text().strip_edges().is_empty() else " — " + stderr_text().strip_edges(),
	]
	return false


func stop() -> void:
	stderr_text()
	if pid > 0:
		if OS.is_process_running(pid):
			OS.kill(pid)
		pid = -1
	cleanup_stderr_file()


## Poll a TCP connect until it succeeds (1), the child exits early (-1), or timeout (0).
func _wait_until_listening(candidate: int, spawned_pid: int) -> int:
	for _attempt in range(60):
		if not OS.is_process_running(spawned_pid):
			await _sleep_ms(50)
			return -1
		var probe := StreamPeerTCP.new()
		if probe.connect_to_host(HOST, candidate) == OK:
			for _spin in range(20):
				probe.poll()
				var status := probe.get_status()
				if status == StreamPeerTCP.STATUS_CONNECTED:
					probe.disconnect_from_host()
					# Give the sidecar a moment to free the slot this probe just took —
					# the server serves ONE client, and the probe was that client.
					await _sleep_ms(60)
					return 1
				if status == StreamPeerTCP.STATUS_ERROR:
					break
				await _sleep_ms(10)
		probe.disconnect_from_host()
		await _sleep_ms(100)
	return 0


func _sleep_ms(ms: int) -> void:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var timer := (loop as SceneTree).create_timer(float(ms) / 1000.0)
		await timer.timeout
	else:
		OS.delay_msec(ms)

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


## Resolve the engine checkout. Env var first, then a sibling directory.
##
## No rig-specific absolute path: this repo is public and a hard-coded `E:/AI/...`
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


## Spawn `node bin.js sidecar <pack> --seed <n> --listen <port>`.
## Returns true on success; `failure` explains any false.
func start(pack_id: String, seed: int) -> bool:
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

	for candidate: int in CANDIDATE_PORTS:
		var args := [bin, "sidecar", pack_id, "--seed", str(seed), "--listen", str(candidate)]
		var spawned := OS.create_process("node", args, false)
		if spawned <= 0:
			failure = "OS.create_process('node') failed — is node on PATH?"
			return false

		if await _wait_until_listening(candidate):
			pid = spawned
			port = candidate
			return true

		# That port did not come up. Reap before trying the next one, so a failed
		# attempt cannot leave a process holding a port for the rest of the suite.
		OS.kill(spawned)
		await _sleep_ms(120)

	failure = "no candidate port came up: %s" % str(CANDIDATE_PORTS)
	return false


func stop() -> void:
	if pid > 0:
		OS.kill(pid)
		pid = -1


## Poll a TCP connect until it succeeds, up to ~6s. Node's startup plus pack boot is
## comfortably under that; a slower machine gets the same answer, later.
func _wait_until_listening(candidate: int) -> bool:
	for _attempt in range(60):
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
					return true
				if status == StreamPeerTCP.STATUS_ERROR:
					break
				await _sleep_ms(10)
		probe.disconnect_from_host()
		await _sleep_ms(100)
	return false


func _sleep_ms(ms: int) -> void:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var timer := (loop as SceneTree).create_timer(float(ms) / 1000.0)
		await timer.timeout
	else:
		OS.delay_msec(ms)

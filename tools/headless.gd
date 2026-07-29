## headless.gd — the stage's test runner.
##
##   godot --headless --path . --script res://tools/headless.gd
##   godot --headless --path . --script res://tools/headless.gd -- --only=scene_join
##
## Discovers `res://tests/test_*.gd`, runs each one's `run(t)` against a fresh
## assertion harness, and prints the structured output the CI job reads. Exits
## non-zero on any failure, on a test that asserted nothing, and on discovering
## no tests at all — an empty run is a failure, not a pass.
extends SceneTree

const TestCase := preload("res://tools/test_case.gd")
const TESTS_DIR := "res://tests"

var _total_checks: int = 0
var _total_pass: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	var only := _arg("only")

	print("=== AI RPG STAGE — HEADLESS ===")
	print("godot=%s" % Engine.get_version_info().get("string", "unknown"))

	var scripts := _discover()
	if scripts.is_empty():
		print("FAIL: no tests discovered under %s" % TESTS_DIR)
		print("verdict=FAIL")
		quit(1)
		return

	var ran := 0
	for path: String in scripts:
		var name := path.get_file().trim_prefix("test_").trim_suffix(".gd")
		if not only.is_empty() and name != only:
			continue
		_run_one(path, name)
		ran += 1

	# A filter that selected nothing is a typo, and reporting PASS for it would be
	# a vacuous green of exactly the kind this runner refuses elsewhere. Caught
	# while proving the runner could go red — the two other controls passed and
	# this path did not.
	if ran == 0:
		print("")
		print("FAIL: --only=%s matched no test (known: %s)" % [only, ", ".join(_names(scripts))])
		_failures.append("filter matched nothing")

	print("")
	print("checks=%d" % _total_checks)
	print("passed=%d" % _total_pass)
	print("failed=%d" % _failures.size())
	var ok := _failures.is_empty()
	print("verdict=%s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


func _run_one(path: String, name: String) -> void:
	print("")
	print("── %s ──" % name)

	var script: Variant = load(path)
	if script == null:
		_fail(name, "could not load %s" % path)
		return

	var suite: Variant = (script as GDScript).new()
	if not suite.has_method("run"):
		_fail(name, "%s has no run(t) method" % path)
		return

	var t: RefCounted = TestCase.new()
	suite.call("run", t)

	var checks: int = t.get("checks_run")
	var passes: Array = t.get("passes")
	var failures: Array = t.get("failures")

	_total_checks += checks
	_total_pass += passes.size()

	for p: Variant in passes:
		print("PASS: %s" % p)
	for f: Variant in failures:
		print("FAIL: %s" % f)
		_failures.append("%s: %s" % [name, f])

	# A test that ran clean without asserting anything is the vacuous green this
	# studio has shipped before. It fails here.
	if checks == 0:
		print("FAIL: %s asserted nothing" % name)
		_failures.append("%s: asserted nothing" % name)


func _fail(name: String, detail: String) -> void:
	print("FAIL: %s" % detail)
	_failures.append("%s: %s" % [name, detail])


func _discover() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(TESTS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir() and entry.begins_with("test_") and entry.ends_with(".gd"):
			out.append("%s/%s" % [TESTS_DIR, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _names(scripts: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for p: String in scripts:
		out.append(p.get_file().trim_prefix("test_").trim_suffix(".gd"))
	return out


## Read `--key=value` from the args after `--`.
func _arg(key: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return ""

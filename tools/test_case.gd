## test_case.gd — the assertion harness every stage test runs under.
##
## Deliberately tiny and deliberately not GUT/gdUnit: this repo has one test
## runner, it runs headless in CI, and a third-party addon would be a dependency
## on the studio's own critical path for value a hundred lines buys outright.
##
## Two properties are load-bearing:
##
##   1. **A test that asserts nothing FAILS.** `checks_run == 0` is reported as a
##      failure, not a pass. A suite of empty tests is the most expensive kind of
##      green, and this studio has shipped vacuous gates before.
##   2. **Failures carry the values.** `expected X, got Y` beats `assertion
##      failed`, every time, at 2am, in a CI log.
##
## Loaded by `preload()` rather than `class_name` so it works before any editor
## import pass has populated the global class cache.
extends RefCounted

var checks_run: int = 0
var passes: Array[String] = []
var failures: Array[String] = []


## The primitive. Everything else is sugar over this.
func check(ok: bool, label: String, detail: String = "") -> bool:
	checks_run += 1
	if ok:
		passes.append(label)
	else:
		failures.append(label if detail.is_empty() else "%s — %s" % [label, detail])
	return ok


func equals(actual: Variant, expected: Variant, label: String) -> bool:
	return check(
		actual == expected,
		label,
		"expected %s, got %s" % [_show(expected), _show(actual)],
	)


func not_equals(actual: Variant, forbidden: Variant, label: String) -> bool:
	return check(actual != forbidden, label, "both sides are %s" % _show(forbidden))


func is_true(actual: bool, label: String) -> bool:
	return check(actual, label, "expected true")


func is_false(actual: bool, label: String) -> bool:
	return check(not actual, label, "expected false")


func contains(haystack: Variant, needle: Variant, label: String) -> bool:
	var found := false
	if haystack is String and needle is String:
		found = (haystack as String).contains(needle as String)
	elif haystack is Array:
		found = (haystack as Array).has(needle)
	elif haystack is Dictionary:
		found = (haystack as Dictionary).has(needle)
	else:
		return check(false, label, "contains() cannot search a %s" % type_string(typeof(haystack)))
	return check(found, label, "%s does not contain %s" % [_show(haystack), _show(needle)])


func not_contains(haystack: Variant, needle: Variant, label: String) -> bool:
	var absent := false
	if haystack is String and needle is String:
		absent = not (haystack as String).contains(needle as String)
	elif haystack is Array:
		absent = not (haystack as Array).has(needle)
	elif haystack is Dictionary:
		absent = not (haystack as Dictionary).has(needle)
	else:
		return check(false, label, "not_contains() cannot search a %s" % type_string(typeof(haystack)))
	return check(absent, label, "%s unexpectedly contains %s" % [_show(haystack), _show(needle)])


## Set equality, reported as the two asymmetric differences.
##
## "these sets differ" sends a reader hunting; "missing [a], unexpected [b]" tells
## them which direction broke, which for a join is the whole diagnosis.
func same_set(actual: Array, expected: Array, label: String) -> bool:
	var missing: Array = []
	var unexpected: Array = []
	for e: Variant in expected:
		if not actual.has(e):
			missing.append(e)
	for a: Variant in actual:
		if not expected.has(a):
			unexpected.append(a)
	return check(
		missing.is_empty() and unexpected.is_empty(),
		label,
		"missing %s, unexpected %s" % [_show(missing), _show(unexpected)],
	)


func _show(v: Variant) -> String:
	if v is String:
		return "'%s'" % v
	if v is Array:
		var parts: Array[String] = []
		for item: Variant in v:
			parts.append(_show(item))
		return "[%s]" % ", ".join(parts)
	return str(v)

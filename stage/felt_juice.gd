## felt_juice.gd — the lie budget.
##
## Camera trauma and flashes keyed off committed UiEffects. Never writes a
## hashed entity or zone transform. Independently killable (WCAG 2.3.1 / XAG 117)
## without changing the sim hash.
extends Node

var enabled := true
var last_offset := Vector2.ZERO

const SHAKE := Vector2(3, 2)


func apply(effects: Array, camera: Camera2D) -> void:
	if camera == null:
		return
	if not enabled:
		camera.offset = Vector2.ZERO
		last_offset = Vector2.ZERO
		return
	for item: Variant in effects:
		if not (item is Dictionary):
			continue
		var kind := String((item as Dictionary).get("type", ""))
		if kind == "shake" or kind == "flash" or kind == "border-pulse":
			camera.offset = SHAKE
			last_offset = camera.offset
			var duration := float((item as Dictionary).get("durationMs", 180))
			_reset_later(camera, duration)


func _reset_later(camera: Camera2D, duration_ms: float) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(maxf(duration_ms, 1.0) / 1000.0).timeout
	if is_instance_valid(camera):
		camera.offset = Vector2.ZERO
		last_offset = Vector2.ZERO

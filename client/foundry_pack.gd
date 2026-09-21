## foundry_pack.gd — load a Sprite Foundry HD pack from its pack.json.
##
## This is the presentation TOOL the stage was missing. Characters are not
## loose folders we rename; they are a schema 2.0.0 pack: tileSize, pivot,
## 8 directions, 4 layers (albedo, normal, mask[R=AO,G=roughness,B=emissive],
## depth). The binder consumes one of these. Anything else is a sticker.
extends RefCounted

const SCHEMA := "2.0.0"
const LAYERS := ["albedo", "normal", "mask", "depth"]


static func load_pack(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var pack: Dictionary = parsed
	if String(pack.get("schema_version", pack.get("schemaVersion", ""))) != "" \
			and String(pack.get("schema_version", pack.get("schemaVersion", SCHEMA))) != SCHEMA:
		# townsfolk-hd uses schema_version 2.0.0; accept either key.
		pass
	return pack


static func canvas_texture(character_root: String, direction: String) -> CanvasTexture:
	var albedo := "%s/albedo/%s.png" % [character_root, direction]
	if not ResourceLoader.exists(albedo):
		return null
	var tex := CanvasTexture.new()
	tex.diffuse_texture = load(albedo)
	var normal := "%s/normal/%s.png" % [character_root, direction]
	if ResourceLoader.exists(normal):
		tex.normal_texture = load(normal)
	var mask := "%s/mask/%s.png" % [character_root, direction]
	if ResourceLoader.exists(mask):
		tex.specular_texture = load(mask)
	tex.specular_color = Color(0.35, 0.32, 0.28, 1)
	tex.specular_shininess = 0.28
	return tex

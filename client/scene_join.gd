## scene_join.gd — bind wire zone ids to scene nodes.
##
## This is a PRODUCTION client component, not a test helper. It is the seam where
## the two halves of the studio meet: the simulation speaks in zone ids, the scene
## is a tree of nodes, and every later phase — re-dressing a town on a state
## shock, populating a zone from a spawn set, rendering a refusal at a door —
## needs to turn one into the other and be sure it got the right node.
##
## What the exporter guarantees (measured, world-forge scene-builder.ts:168-181):
##
##   * every ZONE is a direct child of the scene root carrying `metadata/zone_id`
##   * many DESCENDANTS also carry `metadata/zone_id` naming their owning zone —
##     props, entity instances, markets, spawn markers, transitions
##
## So "nodes with a zone_id" is NOT "zones", and a joiner that conflated them
## would report three zones as eleven and be wrong in a way that still looks like
## it works. The depth discriminator is structural and comes from the generator,
## not from a naming convention that could drift.
##
## The stage never adjudicates. `metadata/entry_gate*` is present in exported
## scenes and this module deliberately offers no way to evaluate it: gates are
## engine rules (the sim compiles the condition grammar and refuses with the
## authored reason). Reading gate text here to predict a refusal would be the
## client deciding, which the contract forbids.
extends RefCounted

const ZONE_ID_KEY := "zone_id"

## zone id -> the zone's root node.
var zones: Dictionary = {}
## zone id -> Array[Node] of descendants tagged with that zone.
var tagged: Dictionary = {}
## Nodes carrying a zone_id that names a zone with no zone node in this scene.
var orphan_tags: Array[String] = []


## Walk a scene and index it. `scene_root` is the instantiated world scene.
func index(scene_root: Node) -> void:
	zones.clear()
	tagged.clear()
	orphan_tags.clear()

	# Pass 1 — the zones. Direct children only, by the exporter's contract.
	for child: Node in scene_root.get_children():
		var id := _zone_id_of(child)
		if id.is_empty():
			continue
		if zones.has(id):
			# Two root-level nodes claiming one zone id. Not a warning: every later
			# phase does `zones[id]` and would silently address one of them
			# forever. Surfaced as an orphan-class defect so a caller can refuse.
			orphan_tags.append("duplicate zone node for '%s'" % id)
			continue
		zones[id] = child
		tagged[id] = [] as Array[Node]

	# Pass 2 — everything else that names a zone.
	for child: Node in scene_root.get_children():
		_collect_tagged(child, not _zone_id_of(child).is_empty())


func zone_ids() -> Array[String]:
	var ids: Array[String] = []
	for k: Variant in zones.keys():
		ids.append(k as String)
	ids.sort()
	return ids


func zone_node(zone_id: String) -> Node:
	return zones.get(zone_id, null) as Node


func tagged_nodes(zone_id: String) -> Array[Node]:
	return tagged.get(zone_id, [] as Array[Node]) as Array[Node]


## Reconcile the indexed scene against the wire's zone ids, BOTH directions.
##
## One direction is not a join. A scene carrying a zone the sim never sends is a
## node no event will ever reach; a zone the sim sends with no node is an event
## the stage will silently drop. Both are the same defect wearing different
## clothes and both have to be named.
func reconcile(wire_zone_ids: Array) -> Dictionary:
	var scene_ids := zone_ids()

	var missing_in_scene: Array[String] = []
	for id: Variant in wire_zone_ids:
		if not scene_ids.has(id):
			missing_in_scene.append(id as String)

	var missing_in_wire: Array[String] = []
	for id: String in scene_ids:
		if not wire_zone_ids.has(id):
			missing_in_wire.append(id)

	var bad_tags: Array[String] = []
	for zone_id: Variant in tagged.keys():
		if not wire_zone_ids.has(zone_id):
			bad_tags.append(zone_id as String)

	return {
		"ok": missing_in_scene.is_empty()
			and missing_in_wire.is_empty()
			and orphan_tags.is_empty()
			and bad_tags.is_empty(),
		"scene_zone_ids": scene_ids,
		"wire_zone_ids": wire_zone_ids,
		# A zone the sim will send events about, with nothing on stage to receive them.
		"missing_in_scene": missing_in_scene,
		# A node on stage the sim has never heard of.
		"missing_in_wire": missing_in_wire,
		# A descendant tagged with a zone id that resolves to no zone node.
		"orphan_tags": orphan_tags,
		# A zone node whose id the wire does not carry, reached via a tag.
		"tagged_zones_absent_from_wire": bad_tags,
	}


func _zone_id_of(node: Node) -> String:
	if not node.has_meta(ZONE_ID_KEY):
		return ""
	var v: Variant = node.get_meta(ZONE_ID_KEY)
	return v as String if v is String else ""


func _collect_tagged(node: Node, inside_zone: bool) -> void:
	var id := _zone_id_of(node)
	if not id.is_empty() and not inside_zone:
		# A tagged node that is NOT under its own zone's subtree. Legal in the
		# exported shape (a transition names the zone it leads to), so it is
		# recorded rather than refused — but recorded, because an unresolvable one
		# is a real defect.
		pass
	if not id.is_empty():
		if tagged.has(id):
			if not zones.get(id, null) == node:
				(tagged[id] as Array).append(node)
		else:
			var label := "%s tagged zone '%s', which has no zone node" % [node.name, id]
			if not orphan_tags.has(label):
				orphan_tags.append(label)
	for child: Node in node.get_children():
		_collect_tagged(child, inside_zone)

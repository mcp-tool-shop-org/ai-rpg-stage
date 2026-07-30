## dressing.gd — swap what a place looks like without moving what it is.
##
## THE RULE THIS ENFORCES, and it is the whole reason the module is separate: state
## flags swap DRESSING, never LAYOUT (Triangle Strategy; Octopath II's day/night flip
## does exactly this — lighting, dressing and NPC distribution change on a FIXED map).
## Suikoden II's Ryube lands because the player knew the town before it changed, and
## that only works if it is recognisably the same town afterwards.
##
## So this module can show and hide nodes. It cannot move one, cannot resize one, and
## cannot add or remove one. That is a deliberate ceiling, asserted by a test: a
## re-dress that relocated a crate would be a different quay, and the shock would read
## as a loading error rather than as a consequence.
##
## HOW A NODE DECLARES ITSELF DRESSING.
##
## By GROUP, which is Godot's own idiom for cross-scene sets and survives an exported
## scene being regenerated. A node in group `dressing:damaged` is visible exactly when
## the sim's `variantTags` carry `dressing:damaged`.
##
## The tags come from the engine's `variantTagsFor(condition)` and are STABLE KEYS by
## contract — the client binds to `dressing:damaged`, never to an asset path:
##
##   intact     dressing:intact
##   strained   dressing:strained  props:sparse
##   damaged    dressing:damaged   lighting:dim  props:rubble
##   ruined     dressing:ruined    lighting:dim  props:rubble
##   occupied   dressing:occupied  props:checkpoint
extends Node

## Prefixes this module owns. `lighting:*` is deliberately NOT here — that belongs to
## the light rig, and a key handled in two places is a key that will one day be handled
## twice differently.
const OWNED_PREFIXES := ["dressing:", "props:"]

## Groups seen at least once, so `known_groups()` can report what a scene actually
## offers rather than what the vocabulary theoretically contains.
var _seen: Dictionary = {}
var _active: Array[String] = []


## Register a node as belonging to a dressing variant.
##
## Called by the scene builder for nodes it creates, and usable from the editor by
## adding the group by hand — the group is the contract, not this function.
func register(node: Node, tag: String) -> void:
	if not _owns(tag):
		push_warning("dressing.register: '%s' is not a dressing tag; ignoring" % tag)
		return
	node.add_to_group(tag)
	_seen[tag] = true


## Apply a set of variant tags: every owned group is hidden, then the named ones shown.
##
## Hide-all-then-show is the only ordering that is idempotent. Toggling only what
## changed leaves the scene dependent on the order shocks arrived in, and after two
## state changes nobody can say what should be visible.
## ⚠ SCOPED TO ONE ZONE, and this was found by LOOKING at the render rather than by any
## test. `world.zone.state.changed` names exactly one zone. The first version toggled
## groups across the whole tree, so a shock to the Long Quay put rubble in the counting
## house, the warehouse, the customs shed and the warren — every room in the town damaged
## because one quay was. The screenshot showed it immediately; 52 green tests did not.
##
## `within` is the zone's node. Godot's groups are global, so membership is filtered by
## ANCESTRY here — which is also what keeps a zone's dressing addressable without a
## per-zone group name that would have to be kept in sync with the export.
func apply(variant_tags: Array, within: Node = null) -> void:
	_active.clear()

	for tag: Variant in _seen.keys():
		_set_group_visible(String(tag), false, within)

	for tag: Variant in variant_tags:
		var t := String(tag)
		if not _owns(t):
			continue # `lighting:*` belongs to the rig
		_seen[t] = true
		_set_group_visible(t, true, within)
		_active.append(t)


func active_tags() -> Array[String]:
	var out := _active.duplicate()
	out.sort()
	return out


func known_groups() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in _seen.keys():
		out.append(String(k))
	out.sort()
	return out


## Every node currently visible because of a dressing tag, optionally within one zone.
func visible_dressing(within: Node = null) -> Array[Node]:
	var out: Array[Node] = []
	var tree := get_tree()
	if tree == null:
		return out
	for tag: String in _active:
		for n: Node in tree.get_nodes_in_group(tag):
			if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
				if within == null or within.is_ancestor_of(n):
					out.append(n)
	return out


static func _owns(tag: String) -> bool:
	for p: String in OWNED_PREFIXES:
		if tag.begins_with(p):
			return true
	return false


## ⚠ USES ITS OWN TREE, not a caller-supplied root.
##
## The first version took a `scene_root: Node` and called `get_tree()` on it. That was
## redundant — this is a Node, already in the tree — and it logged
## `Parameter "data.tree" is null` twice per build, because Godot emits that error from
## `get_tree()` itself BEFORE returning null, so the null-guard below silenced the
## consequence while leaving the noise. Errors nobody can act on are how a log stops
## being read.
func _set_group_visible(tag: String, visible: bool, within: Node = null) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for n: Node in tree.get_nodes_in_group(tag):
		if n is CanvasItem and (within == null or within.is_ancestor_of(n)):
			(n as CanvasItem).visible = visible

## test_fallback_rendering.gd — fallback transcript lines for events outside RENDERED.
extends RefCounted

const Diorama := preload("res://stage/diorama.gd")
const NetworkClient := preload("res://client/network_client.gd")
const EventBus := preload("res://client/event_bus.gd")
const Session := preload("res://stage/session.gd")


func run_async(t: RefCounted) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		t.check(false, "SceneTree available")
		return

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
	session.call("set_player_id", "player")

	# 1. Unknown event type produces exactly one fallback line naming type and sorted payload keys.
	var unknown_ev := {
		"id": "ev-unknown-1",
		"tick": 1,
		"type": "combat.contact.hit",
		"payload": {"targetId": "npc-drell", "damage": 4, "actorId": "player"},
	}
	await session.call("_present", unknown_ev)
	var tx_after_unknown: Array = (session.get("transcript") as Array).duplicate()
	t.equals(tx_after_unknown.size(), 1, "unknown event produces exactly one fallback line")
	if tx_after_unknown.size() > 0:
		var line := String(tx_after_unknown[0])
		t.contains(line, Session.FALLBACK_TAG, "fallback line uses the distinct fallback tag")
		t.contains(line, Session.FALLBACK_COLOR, "fallback line uses the distinct fallback style")
		t.contains(line, "combat.contact.hit", "fallback line names the event type")
		t.contains(line, "actorId, damage, targetId", "fallback line lists payload keys in sorted order")

	# Unknown event with empty payload still produces one fallback line naming its type.
	await session.call("_present", {"id": "ev-unknown-2", "tick": 2, "type": "world.custom.ping", "payload": {}})
	var tx_after_empty: Array = (session.get("transcript") as Array).duplicate()
	t.equals(tx_after_empty.size(), 2, "empty-payload unknown event still adds one fallback line")
	if tx_after_empty.size() >= 2:
		t.contains(String(tx_after_empty[1]), "world.custom.ping", "empty-payload fallback names event type")

	# 2. Every RENDERED event type goes through its bespoke handler and emits NO fallback line.
	var start_idx := tx_after_empty.size()
	for ev: Dictionary in [
		{"type": "world.zone.entered", "actorId": "player", "payload": {"zoneId": "long-quay"}},
		{"type": "world.zone.state.changed", "payload": {"zoneId": "long-quay", "zoneName": "The Long Quay", "variantTags": ["damaged"], "from": "intact", "to": "damaged", "cause": "stability"}},
		{"type": "world.zone.gate.refused", "payload": {"reason": "Seal, or nothing."}},
		{"type": "action.rejected", "payload": {"verb": "yodel", "reason": "No such verb."}},
		{"type": "encounter.spawned", "payload": {"zoneId": "crooked-stair", "spawnedEntityIds": ["npc-probe"]}},
	]:
		await session.call("_present", ev)

	var tx_final: Array = session.get("transcript") as Array
	t.check(tx_final.size() > start_idx, "RENDERED handlers added bespoke transcript lines")
	var fallback_on_rendered := 0
	for i in range(start_idx, tx_final.size()):
		if String(tx_final[i]).contains(Session.FALLBACK_TAG):
			fallback_on_rendered += 1
	t.equals(fallback_on_rendered, 0, "RENDERED event types produce zero fallback lines")

	session.queue_free()
	d.queue_free()
	client.queue_free()
	bus.queue_free()
	await tree.process_frame

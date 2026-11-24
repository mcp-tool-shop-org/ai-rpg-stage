## test_actor_gate.gd — proves only the player's own `world.zone.entered` moves the player.
##
## Driven against both:
##   1. A live mock-wire `NetworkClient` (`initialize` + `snapshot` carrying non-default
##      `playerId`, `submitAction` for the player move, `advance` for follower and
##      missing-`actorId` round events) + `Diorama` + `Session`.
##   2. The actual `ai-rpg-engine` sidecar with Salt Road content, confirming `player_id()`
##      resolves from the real handshake/snapshot and non-player / unattributed
##      `world.zone.entered` events leave the player node, `_player_zone`, and
##      transcript untouched.
extends RefCounted

const Harness := preload("res://tools/sidecar_harness.gd")
const Framing := preload("res://client/framing.gd")
const StateDigest := preload("res://client/state_digest.gd")
const NetworkClient := preload("res://client/network_client.gd")
const EventBus := preload("res://client/event_bus.gd")
const Diorama := preload("res://stage/diorama.gd")
const Session := preload("res://stage/session.gd")

const HOST_PACK := "chapel-threshold"
const SEED := 71


func run_async(t: RefCounted) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		t.check(false, "a SceneTree is available", "actor gate tests require frames")
		return

	await _test_mock_wire_actor_gate(t, tree)
	await _test_uninitialized_session_fails_closed(t, tree)
	await _test_live_sidecar_actor_gate(t, tree)


func _test_mock_wire_actor_gate(t: RefCounted, tree: SceneTree) -> void:
	var srv := TCPServer.new()
	if srv.listen(0, "127.0.0.1") != OK:
		t.check(false, "mock server listening for actor_gate", "TCPServer.listen failed")
		return
	var port := srv.get_local_port()

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

	var entered_signals: Array[String] = []
	session.zone_entered.connect(func(z: String) -> void: entered_signals.append(z))

	# Snapshot updates playerId from handshake "pilgrim" -> authoritative mirror "factor"
	# (non-default id proving the stage does not hard-code "player").
	var snap_state := {"playerId": "factor", "items": []}
	var snap_canon := StateDigest.canonical_state_hash(snap_state)

	var peer_box := {"peer": null, "buf": PackedByteArray(), "framing": Framing.new()}
	var pump_server := func(on_request: Callable) -> void:
		if srv.is_connection_available() and peer_box["peer"] == null:
			var p := srv.take_connection()
			p.set_no_delay(true)
			peer_box["peer"] = p
		var p: StreamPeerTCP = peer_box["peer"]
		if p == null:
			return
		p.poll()
		if p.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return
		var av := p.get_available_bytes()
		if av <= 0:
			return
		var g := p.get_partial_data(av)
		if int(g[0]) != OK:
			return
		var b := peer_box["buf"] as PackedByteArray
		b.append_array(g[1] as PackedByteArray)
		var fr := peer_box["framing"] as RefCounted
		for msg: Variant in fr.push(b):
			b.clear()
			if msg is Dictionary:
				on_request.call(p, msg as Dictionary)

	# 1. Attach learns playerId from initialize before baseline snapshot arrives.
	var attach_state := {"done": false, "res": {}}
	var run_attach := func() -> void:
		attach_state["res"] = await client.call("attach", "127.0.0.1", port, "stage/actor-gate-test", "0.1.0")
		attach_state["done"] = true
	run_attach.call()

	for _f in range(180):
		pump_server.call(func(p: StreamPeerTCP, m: Dictionary) -> void:
			if String(m.get("method", "")) == "initialize":
				p.put_data(Framing.encode({
					"jsonrpc": "2.0",
					"id": m.get("id", 1),
					"result": {
						"serverName": "mock",
						"engineVersion": "0.0.0",
						"digest_spec_version": 2,
						"playerId": "pilgrim",
						"capabilities": {"hashes": true, "canonicalHashes": true, "audio": true},
						"tick": 0,
					},
				}))
		)
		if bool(attach_state["done"]):
			break
		await tree.process_frame

	t.is_true(bool(attach_state["done"]), "mock client attach completed")
	t.equals(String(client.call("player_id")), "pilgrim", "NetworkClient learns non-default playerId from handshake")
	t.equals(String(session.call("player_id")), "pilgrim", "Session resolves player_id from handshake before snapshot")

	# 2. Baseline snapshot overrides playerId cleanly from authoritative world mirror.
	var snap_done := {"done": false}
	var run_snap := func() -> void:
		await client.call("snapshot")
		snap_done["done"] = true
	run_snap.call()

	for _s in range(180):
		pump_server.call(func(p: StreamPeerTCP, m: Dictionary) -> void:
			if String(m.get("method", "")) == "snapshot":
				p.put_data(Framing.encode({
					"jsonrpc": "2.0",
					"id": m.get("id", 2),
					"result": {
						"tick": 0,
						"hash": "h0",
						"canonicalHash": snap_canon,
						"snapshotSeq": 1,
						"delta": [{"op": "add", "path": [], "value": snap_state}],
					},
				}))
		)
		if bool(snap_done["done"]):
			break
		await tree.process_frame

	t.is_true(bool(snap_done["done"]), "mock baseline snapshot completed")
	t.equals(String(client.call("player_id")), "factor", "NetworkClient updates playerId from authoritative snapshot mirror")
	t.equals(String(session.call("player_id")), "factor", "Session resolves updated player_id from mirror")

	# 3. Player's own world.zone.entered moves the player node, _player_zone, and transcript.
	var walk_done := {"done": false, "res": {}}
	var run_walk := func() -> void:
		walk_done["res"] = await session.call("walk_to", "weighing-floor")
		walk_done["done"] = true
	run_walk.call()

	for _w in range(240):
		pump_server.call(func(p: StreamPeerTCP, m: Dictionary) -> void:
			if String(m.get("method", "")) == "submitAction":
				p.put_data(Framing.encode({
					"jsonrpc": "2.0",
					"id": m.get("id", 3),
					"result": {
						"tick": 1,
						"hash": "h1",
						"canonicalHash": snap_canon,
						"snapshotSeq": 1,
						"delta": [],
						"events": [{
							"id": "ev-player-enter",
							"tick": 1,
							"type": "world.zone.entered",
							"actorId": "factor",
							"payload": {
								"zoneId": "weighing-floor",
								"zoneName": "The Weighing Floor",
								"previousZoneId": "counting-house",
							},
						}],
					},
				}))
		)
		if bool(walk_done["done"]):
			break
		await tree.process_frame

	t.is_true(bool(walk_done["done"]), "player walk_to RPC completed")
	var player_node: Node2D = d.get("player")
	var weighing_node: Node2D = d.call("zone_node", "weighing-floor") as Node2D
	var weighing_prose := String(d.call("description_of", "weighing-floor"))
	var iso: Node = d.get("iso")

	t.equals(String(session.call("player_zone")), "weighing-floor",
		"player's own world.zone.entered updates _player_zone to destination")
	t.is_true(player_node != null and weighing_node != null and player_node.get_parent() == weighing_node,
		"player's own world.zone.entered moves player node into destination zone node")
	if iso != null:
		t.equals(String(iso.get("current_zone")), "weighing-floor",
			"player's own world.zone.entered updates iso current_zone")
	t.equals(entered_signals, ["weighing-floor"],
		"player's own world.zone.entered emits zone_entered once with destination zone")

	var tx_after_player: Array = (session.get("transcript") as Array).duplicate()
	var saw_player_line := false
	for line: Variant in tx_after_player:
		if String(line) == weighing_prose:
			saw_player_line = true
	t.is_true(saw_player_line, "player's own world.zone.entered appends room prose to transcript")

	# 4. Non-player actor (follower) emitting world.zone.entered leaves player node,
	#    _player_zone, transcript, and zone_entered signal untouched.
	var adv_done := {"done": false}
	var run_follower_adv := func() -> void:
		await session.call("advance")
		adv_done["done"] = true
	run_follower_adv.call()

	for _a in range(240):
		pump_server.call(func(p: StreamPeerTCP, m: Dictionary) -> void:
			if String(m.get("method", "")) == "advance":
				p.put_data(Framing.encode({
					"jsonrpc": "2.0",
					"id": m.get("id", 4),
					"result": {
						"tick": 2,
						"hash": "h2",
						"canonicalHash": snap_canon,
						"snapshotSeq": 1,
						"delta": [],
						"events": [{
							"id": "ev-follower-step",
							"tick": 2,
							"type": "world.zone.entered",
							"actorId": "npc-follower-corvane",
							"payload": {
								"zoneId": "long-quay",
								"zoneName": "The Long Quay",
								"previousZoneId": "crooked-stair",
							},
						}],
					},
				}))
		)
		if bool(adv_done["done"]):
			break
		await tree.process_frame

	t.is_true(bool(adv_done["done"]), "follower round advance completed cleanly")
	await session.call("_present", {
		"id": "ev-follower-direct",
		"tick": 2,
		"type": "world.zone.entered",
		"actorId": "npc-follower-corvane",
		"payload": {"zoneId": "customs-shed"},
	})

	t.equals(String(session.call("player_zone")), "weighing-floor",
		"follower world.zone.entered leaves _player_zone unchanged")
	t.is_true(player_node.get_parent() == weighing_node,
		"follower world.zone.entered leaves player node in weighing-floor")
	if iso != null:
		t.equals(String(iso.get("current_zone")), "weighing-floor",
			"follower world.zone.entered leaves iso current_zone unchanged")
	t.equals((session.get("transcript") as Array), tx_after_player,
		"follower world.zone.entered leaves transcript and player room line unchanged")
	t.equals(entered_signals.size(), 1,
		"follower world.zone.entered does not emit zone_entered")

	# 5. Events missing top-level `actorId` (absent, null, empty, whitespace, non-string, or
	#    nested inside payload) fail closed as not-the-player — unattributed events never
	#    teleport the player node, mutate _player_zone, or emit room prose.
	var missing_cases: Array[Dictionary] = [
		{"id": "ev-miss-1", "tick": 3, "type": "world.zone.entered", "payload": {"zoneId": "long-quay"}},
		{"id": "ev-miss-2", "tick": 3, "type": "world.zone.entered", "actorId": null, "payload": {"zoneId": "bonded-warehouse"}},
		{"id": "ev-miss-3", "tick": 3, "type": "world.zone.entered", "actorId": "", "payload": {"zoneId": "customs-shed"}},
		{"id": "ev-miss-4", "tick": 3, "type": "world.zone.entered", "actorId": "   ", "payload": {"zoneId": "crooked-stair"}},
		{"id": "ev-miss-5", "tick": 3, "type": "world.zone.entered", "actorId": 7, "payload": {"zoneId": "long-quay"}},
		{"id": "ev-miss-6", "tick": 3, "type": "world.zone.entered", "payload": {"zoneId": "long-quay", "actorId": "factor"}},
	]
	for bad_ev: Dictionary in missing_cases:
		await session.call("_present", bad_ev)

	t.equals(String(session.call("player_zone")), "weighing-floor",
		"missing/invalid actorId world.zone.entered treated as not-the-player (_player_zone unchanged)")
	t.is_true(player_node.get_parent() == weighing_node,
		"missing/invalid actorId world.zone.entered leaves player node unmoved")
	if iso != null:
		t.equals(String(iso.get("current_zone")), "weighing-floor",
			"missing/invalid actorId world.zone.entered leaves iso current_zone unchanged")
	t.equals((session.get("transcript") as Array), tx_after_player,
		"missing/invalid actorId world.zone.entered appends no player or fallback lines")
	t.equals(entered_signals.size(), 1,
		"missing/invalid actorId world.zone.entered does not emit zone_entered")

	if peer_box["peer"] != null:
		(peer_box["peer"] as StreamPeerTCP).disconnect_from_host()
	srv.stop()
	client.call("detach")
	session.queue_free()
	d.queue_free()
	client.queue_free()
	bus.queue_free()
	await tree.process_frame


func _test_uninitialized_session_fails_closed(t: RefCounted, tree: SceneTree) -> void:
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

	var sigs: Array[String] = []
	session.zone_entered.connect(func(z: String) -> void: sigs.append(z))

	# Even with actorId "player", an unattached Session with no learned player_id must fail closed.
	await session.call("_present", {
		"id": "ev-uninit",
		"tick": 1,
		"type": "world.zone.entered",
		"actorId": "player",
		"payload": {"zoneId": "long-quay"},
	})
	t.equals(String(session.call("player_id")), "",
		"unattached Session starts with empty player_id instead of assuming 'player'")
	t.equals(String(session.call("player_zone")), Diorama.PLAYER_START_ZONE,
		"unattached Session with empty player_id refuses to move _player_zone")
	t.equals((session.get("transcript") as Array).size(), 0,
		"unattached Session with empty player_id appends no transcript line")
	t.equals(sigs.size(), 0,
		"unattached Session with empty player_id does not emit zone_entered")

	session.queue_free()
	d.queue_free()
	client.queue_free()
	bus.queue_free()
	await tree.process_frame


func _test_live_sidecar_actor_gate(t: RefCounted, tree: SceneTree) -> void:
	var harness: RefCounted = Harness.new()
	var extra: Array[String] = [
		"--content", Harness.salt_road_pack(),
		"--manifest", Harness.salt_road_manifest(),
		"--start", Diorama.PLAYER_START_ZONE,
	]
	harness.extra_args = extra
	var started: bool = await harness.call("start", HOST_PACK, SEED)
	t.is_true(started, "live sidecar started for actor_gate verification")
	if not started:
		harness.call("stop")
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

	var hs: Dictionary = await client.call("attach", Harness.HOST, int(harness.get("port")), "stage/live-actor-gate", "0.1.0")
	t.is_false(hs.is_empty(), "live client attached to sidecar")
	var live_pid := String(hs.get("playerId", ""))
	t.is_false(live_pid.is_empty(), "real sidecar handshake carries non-empty playerId")
	t.equals(String(session.call("player_id")), live_pid, "Session.player_id matches live handshake playerId")

	var snap: Dictionary = await client.call("snapshot")
	t.is_false(bool(snap.get("__error__", false)), "live baseline snapshot succeeded")

	var move_res: Dictionary = await session.call("walk_to", "weighing-floor")
	t.is_false(bool(move_res.get("__error__", false)), "live player walk_to('weighing-floor') succeeded")
	var player_node: Node2D = d.get("player")
	var weighing_node: Node2D = d.call("zone_node", "weighing-floor") as Node2D
	t.equals(String(session.call("player_zone")), "weighing-floor",
		"live player walk updates _player_zone via sim world.zone.entered")
	t.is_true(player_node != null and weighing_node != null and player_node.get_parent() == weighing_node,
		"live player walk moves player scene node to weighing-floor")

	var tx_before: Array = (session.get("transcript") as Array).duplicate()
	var sigs: Array[String] = []
	session.zone_entered.connect(func(z: String) -> void: sigs.append(z))

	# Enqueue a follower zone entry and an unattributed zone entry through the real tick queue.
	var queue: RefCounted = session.get("queue")
	queue.call("enqueue", [
		{
			"id": "live-follower-enter",
			"tick": 99,
			"type": "world.zone.entered",
			"actorId": "npc-follower-live",
			"payload": {"zoneId": "crooked-stair", "zoneName": "Crooked Stair"},
		},
		{
			"id": "live-unattributed-enter",
			"tick": 100,
			"type": "world.zone.entered",
			"payload": {"zoneId": "long-quay", "zoneName": "The Long Quay"},
		},
	])
	await queue.call("drain")

	t.equals(String(session.call("player_zone")), "weighing-floor",
		"live Session ignores follower and unattributed world.zone.entered (_player_zone intact)")
	t.is_true(player_node.get_parent() == weighing_node,
		"live Session ignores follower and unattributed world.zone.entered (player node intact)")
	t.equals((session.get("transcript") as Array), tx_before,
		"live Session leaves player transcript unchanged on non-player world.zone.entered")
	t.equals(sigs.size(), 0,
		"live Session does not emit zone_entered on non-player world.zone.entered")

	client.call("detach")
	harness.call("stop")
	session.queue_free()
	d.queue_free()
	client.queue_free()
	bus.queue_free()
	await tree.create_timer(0.3).timeout

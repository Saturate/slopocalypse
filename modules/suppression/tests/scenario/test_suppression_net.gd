extends GdUnitTestSuite
## A real server and client in one process over ENet: a near miss the server counts for the
## client's player reaches that client (its value, and a near miss to crack and shake on), and
## the client's copy falls back to 0 on its own as the server's does.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/suppression/suppression_module.gd"

var _server: Node
var _client: Node
var _server_peer: ENetMultiplayerPeer
var _client_peer: ENetMultiplayerPeer
var _near: Array[Dictionary] = []


func _branch(branch_name: String) -> Node:
	var root := Node.new()
	root.name = branch_name
	add_child(root)
	var module: Node = (load(MODULE) as GDScript).new()
	module.name = "Suppression"
	root.add_child(module)
	return root


func before_test() -> void:
	_server = _branch("Server")
	_client = _branch("Client")
	var port := 8180 + randi() % 60
	_server_peer = ENetMultiplayerPeer.new()
	assert_int(_server_peer.create_server(port, 4)).is_equal(OK)
	var server_api := SceneMultiplayer.new()
	server_api.multiplayer_peer = _server_peer
	get_tree().set_multiplayer(server_api, _server.get_path())
	_client_peer = ENetMultiplayerPeer.new()
	assert_int(_client_peer.create_client("127.0.0.1", port)).is_equal(OK)
	var client_api := SceneMultiplayer.new()
	client_api.multiplayer_peer = _client_peer
	get_tree().set_multiplayer(client_api, _client.get_path())
	for i in 120:
		if _client.multiplayer.get_unique_id() > 1 and _server.multiplayer.get_peers().size() == 1:
			break
		await get_tree().process_frame
	_near.clear()
	EventBus.subscribe(&"suppression.near_miss", _on_near_miss)


func after_test() -> void:
	EventBus.unsubscribe(&"suppression.near_miss", _on_near_miss)
	var client_path := _client.get_path()
	var server_path := _server.get_path()
	_client.free()
	_server.free()
	_client_peer.close()
	_server_peer.close()
	get_tree().set_multiplayer(null, client_path)
	get_tree().set_multiplayer(null, server_path)


func _on_near_miss(p: Dictionary) -> void:
	_near.append(p)


func test_the_owning_client_gets_its_suppression() -> void:
	var peer := _client.multiplayer.get_unique_id()
	assert_int(peer).is_greater(1)
	# The server's body for the client's player.
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", peer)
	player.add_to_group(&"players")
	# Not spawned on the client here (no spawner), so nothing to keep in step with there.
	player.get_node("NetSync").free()
	_server.add_child(player)
	player.set_physics_process(false)
	EventBus.publish(&"player.spawned", {"player": player, "local": false})
	var foe: Node3D = auto_free(Node3D.new())
	foe.set_meta(&"team", "enemies")
	_server.add_child(foe)
	var server_module := _server.get_node("Suppression")
	var client_module := _client.get_node("Suppression")
	var chest := player.global_position + Vector3.UP * 1.3
	for i in 2:
		EventBus.publish(&"weapon.fired", {"weapon": null, "holder": foe, "from": chest + Vector3(1, 0, -40), "to": chest + Vector3(1, 0, 40), "target": null, "damage": 0.0})
	var sent := float(server_module.call(&"level_of", peer))
	assert_float(sent).is_greater(0.0)
	for i in 60:
		if _near.size() >= 2:
			break
		await get_tree().process_frame
	# Only the client heard them as its own near misses; the server draws and plays nothing.
	assert_int(_near.size()).is_equal(2)
	assert_float(float(client_module.call(&"local_level"))).is_equal_approx(sent, 0.05)
	assert_vector(_near[0]["position"] as Vector3).is_equal_approx(chest + Vector3(1, 0, 0), Vector3.ONE * 0.01)
	var decay := float((server_module.get(&"config") as Dictionary)["decay_per_second"])
	await get_tree().create_timer(sent / decay + 0.3).timeout
	assert_float(float(client_module.call(&"local_level"))).is_equal(0.0)
	assert_float(float(server_module.call(&"level_of", peer))).is_equal(0.0)

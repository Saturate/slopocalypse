extends GdUnitTestSuite
## A real server and client in one process over ENet, each with its own session (NetSession
## and its NetGate), as in a game. Replication reaches a client only once its hello is
## accepted, and nothing new reaches it from the moment it is being kicked (#552), so a peer
## that was refused has had nothing sent to it while it hangs up. A joining client gets
## everything that already exists right after its hello, with or without a synchronizer.


var _server: Node
var _client: Node
var _server_peer: ENetMultiplayerPeer
var _client_peer: ENetMultiplayerPeer
var _server_net: NetSession
var _client_net: NetSession
var _index := 0


func _make(data: Variant) -> Node:
	var info: Dictionary = data
	var thing := Node3D.new()
	thing.name = str(info["name"])
	thing.position = info["position"]
	if info["synced"]:
		thing.add_child(NetSync.make([".:position"]))
	return thing


func _add_spawner(branch: Node) -> void:
	var spawner := MultiplayerSpawner.new()
	spawner.name = "Spawner"
	spawner.spawn_path = NodePath("..")
	spawner.spawn_function = _make
	branch.add_child(spawner)


func _session(branch: Node) -> NetSession:
	var net: NetSession = (load("res://core/net.gd") as GDScript).new()
	net.name = "Net"
	branch.add_child(net)
	return net


func before_test() -> void:
	_server = auto_free(Node.new())
	_server.name = "Server"
	add_child(_server)
	_client = auto_free(Node.new())
	_client.name = "Client"
	add_child(_client)
	var port := 8040 + randi() % 50
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
	# The server's session sees the connection; the client's comes once connected, so it has
	# not said hello yet: the test says it when it wants to.
	_server_net = _session(_server)
	_add_spawner(_server)
	for i in 120:
		if _client.multiplayer.get_unique_id() > 1 and _server.multiplayer.get_peers().size() == 1:
			break
		await get_tree().process_frame
	_client_net = _session(_client)
	_add_spawner(_client)


func after_test() -> void:
	var client_path := _client.get_path()
	var server_path := _server.get_path()
	# The client's session would quit the run when its server goes away.
	_client.free()
	_server.free()
	_client_peer.close()
	_server_peer.close()
	get_tree().set_multiplayer(null, client_path)
	get_tree().set_multiplayer(null, server_path)


func _spawn(synced: bool) -> String:
	_index += 1
	var thing_name := "Thing%d" % _index
	(_server.get_node("Spawner") as MultiplayerSpawner).spawn({"name": thing_name, "position": Vector3(_index, 0, 0), "synced": synced})
	return thing_name


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _peer() -> int:
	return _server.multiplayer.get_peers()[0]


func _join() -> void:
	_client_net._say_hello()
	for i in 60:
		if _server_net.replicates_to(_peer()):
			break
		await get_tree().process_frame
	assert_bool(_server_net.replicates_to(_peer())).is_true()


func test_nothing_reaches_a_client_before_its_hello_and_everything_after() -> void:
	var plain := _spawn(false)
	var synced := _spawn(true)
	await _frames(20)
	assert_object(_client.get_node_or_null(plain)).is_null()
	assert_object(_client.get_node_or_null(synced)).is_null()
	await _join()
	await _frames(10)
	assert_object(_client.get_node_or_null(plain)).is_not_null()
	assert_object(_client.get_node_or_null(synced)).is_not_null()
	# The one without a synchronizer of its own carries the gate's, on both sides alike.
	assert_object(_client.get_node_or_null(plain + "/" + NetGate.GATE_NAME)).is_not_null()
	assert_object(_server.get_node_or_null(synced + "/" + NetGate.GATE_NAME)).is_null()
	# Spawned after joining: straight through, with its state.
	var later := _spawn(true)
	var thing := _server.get_node(later) as Node3D
	await _frames(10)
	thing.position.y = 5.0
	await _frames(10)
	assert_float((_client.get_node(later) as Node3D).position.y).is_equal_approx(5.0, 0.001)


func test_a_client_being_kicked_is_sent_nothing_new() -> void:
	await _join()
	var before := _spawn(true)
	await _frames(10)
	assert_object(_client.get_node_or_null(before)).is_not_null()
	# What `server_kick` marks besides telling them why (the client would quit on that).
	_server_net._kicking[_peer()] = NetSession.KICK_SECONDS
	assert_bool(_server_net.replicates_to(_peer())).is_false()
	assert_array(_server_net.joined_peers()).is_empty()
	var after_plain := _spawn(false)
	var after_synced := _spawn(true)
	await _frames(20)
	assert_object(_client.get_node_or_null(after_plain)).is_null()
	assert_object(_client.get_node_or_null(after_synced)).is_null()
	# What they already have is not taken back: their own body would go while their game runs.
	assert_object(_client.get_node_or_null(before)).is_not_null()

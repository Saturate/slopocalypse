extends GdUnitTestSuite
## A real server and client in one process (each subtree with its own multiplayer, joined over
## ENet on localhost): things marked `net_relevance` reach the client only while they are near
## its player, spawned with their current state and despawned again past the margin.

const REACH := 50.0
const MARGIN := 10.0

var _server: Node
var _client: Node
var _server_peer: ENetMultiplayerPeer
var _client_peer: ENetMultiplayerPeer
var _relevance: NetRelevance
var _index := 0


func _branch(name: String) -> Node:
	var root := Node.new()
	root.name = name
	add_child(root)
	var world := Node.new()
	world.name = "World"
	root.add_child(world)
	var spawner := MultiplayerSpawner.new()
	spawner.name = "Spawner"
	spawner.spawn_path = NodePath("..")
	spawner.spawn_function = _make
	world.add_child(spawner)
	return root


func _make(data: Variant) -> Node:
	var info: Dictionary = data
	var thing := Node3D.new()
	thing.name = str(info["name"])
	thing.position = info["position"]
	thing.set_meta(&"net_relevance", true)
	thing.add_child(NetSync.make([".:position"]))
	return thing


func before_test() -> void:
	_server = _branch("Server")
	_client = _branch("Client")
	var port := 7840 + randi() % 100
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
	_relevance = NetRelevance.new()
	_server.add_child(_relevance)
	_relevance.reach = REACH
	_relevance.margin = MARGIN
	_relevance.every = 0.0
	for i in 120:
		if _client.multiplayer.get_unique_id() > 1 and _server.multiplayer.get_peers().size() == 1:
			break
		await get_tree().process_frame
	# The client's player, as the server knows it.
	var player := Node3D.new()
	player.add_to_group(&"players")
	player.set_meta(&"peer_id", _client.multiplayer.get_unique_id())
	_server.add_child(player)


func after_test() -> void:
	# The nodes go while their multiplayer still tracks them, then the multiplayers.
	var client_path := _client.get_path()
	var server_path := _server.get_path()
	_client.free()
	_server.free()
	_client_peer.close()
	_server_peer.close()
	get_tree().set_multiplayer(null, client_path)
	get_tree().set_multiplayer(null, server_path)


func _spawn(at: Vector3) -> Node3D:
	_index += 1
	var spawner := _server.get_node("World/Spawner") as MultiplayerSpawner
	return spawner.spawn({"name": "Thing%d" % _index, "position": at}) as Node3D


func _settle() -> void:
	for i in 10:
		await get_tree().process_frame


func _on_client(thing: Node3D) -> Node3D:
	return _client.get_node_or_null("World/" + String(thing.name)) as Node3D


func test_only_near_things_reach_the_client_with_their_state() -> void:
	assert_int(_server.multiplayer.get_peers().size()).is_equal(1)
	var near := _spawn(Vector3(20, 0, 0))
	var far := _spawn(Vector3(200, 0, 0))
	await _settle()
	assert_object(_on_client(near)).is_not_null()
	assert_object(_on_client(far)).is_null()
	# Walks into range: spawned there, where it is now.
	far.position = Vector3(0, 0, 30)
	await _settle()
	var arrived := _on_client(far)
	assert_object(arrived).is_not_null()
	assert_vector(arrived.position).is_equal_approx(Vector3(0, 0, 30), Vector3.ONE * 0.01)


func test_the_margin_stops_it_flickering_at_the_edge() -> void:
	var thing := _spawn(Vector3(40, 0, 0))
	await _settle()
	assert_object(_on_client(thing)).is_not_null()
	# Just past the reach but inside the margin: stays.
	thing.position = Vector3(REACH + MARGIN * 0.5, 0, 0)
	await _settle()
	assert_object(_on_client(thing)).is_not_null()
	# Past the margin: gone.
	thing.position = Vector3(REACH + MARGIN * 1.5, 0, 0)
	await _settle()
	assert_object(_on_client(thing)).is_null()
	# Back inside the margin but not the reach: still gone, so it doesn't come and go.
	thing.position = Vector3(REACH + MARGIN * 0.5, 0, 0)
	await _settle()
	assert_object(_on_client(thing)).is_null()
	thing.position = Vector3(REACH - 5.0, 0, 0)
	await _settle()
	assert_object(_on_client(thing)).is_not_null()


func test_relevance_keeps_a_margin() -> void:
	assert_bool(NetRelevance.relevant(false, 399.0, 400.0, 40.0)).is_true()
	assert_bool(NetRelevance.relevant(false, 420.0, 400.0, 40.0)).is_false()
	assert_bool(NetRelevance.relevant(true, 420.0, 400.0, 40.0)).is_true()
	assert_bool(NetRelevance.relevant(true, 441.0, 400.0, 40.0)).is_false()

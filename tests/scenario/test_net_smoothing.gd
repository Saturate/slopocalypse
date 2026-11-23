extends GdUnitTestSuite
## A real server and client in one process over ENet: on the client, things spawned with the
## `net_smooth` meta are shown a little in the past, blended between server updates; anything
## else (your own player) still lands where the server put it as soon as it arrives.

var _server: Node
var _client: Node
var _server_peer: ENetMultiplayerPeer
var _client_peer: ENetMultiplayerPeer
var _smoothing: NetSmoothing
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
	if info["smooth"]:
		thing.set_meta(&"net_smooth", true)
	var head := Node3D.new()
	head.name = "Head"
	thing.add_child(head)
	thing.add_child(NetSync.make([".:position", ".:rotation:y", "Head:rotation"]))
	return thing


func before_test() -> void:
	_server = _branch("Server")
	_client = _branch("Client")
	var port := 7940 + randi() % 50
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
	_smoothing = NetSmoothing.new()
	_client.add_child(_smoothing)
	for i in 120:
		if _client.multiplayer.get_unique_id() > 1 and _server.multiplayer.get_peers().size() == 1:
			break
		await get_tree().process_frame


func after_test() -> void:
	var client_path := _client.get_path()
	var server_path := _server.get_path()
	_client.free()
	_server.free()
	_client_peer.close()
	_server_peer.close()
	get_tree().set_multiplayer(null, client_path)
	get_tree().set_multiplayer(null, server_path)


func _spawn(at: Vector3, smooth: bool) -> Node3D:
	_index += 1
	var spawner := _server.get_node("World/Spawner") as MultiplayerSpawner
	return spawner.spawn({"name": "Thing%d" % _index, "position": at, "smooth": smooth}) as Node3D


func _settle() -> void:
	for i in 10:
		await get_tree().process_frame
	# Updates land at the start of a frame and the smoothing writes over them in `_process`;
	# the next physics step comes after that, so it sees what was drawn.
	await get_tree().physics_frame


func _on_client(thing: Node3D) -> Node3D:
	return _client.get_node_or_null("World/" + String(thing.name)) as Node3D


func test_only_opted_in_things_are_shown_in_the_past() -> void:
	# Far enough back that nothing newer than the spawn is shown yet.
	_smoothing.delay = 30.0
	var smooth := _spawn(Vector3.ZERO, true)
	var plain := _spawn(Vector3.ZERO, false)
	await _settle()
	assert_int(_smoothing.tracked_count()).is_equal(1)
	smooth.position = Vector3(3, 0, 0)
	smooth.rotation.y = 0.5
	(smooth.get_node("Head") as Node3D).rotation.x = 0.3
	plain.position = Vector3(3, 0, 0)
	await _settle()
	assert_vector(_on_client(plain).position).is_equal_approx(Vector3(3, 0, 0), Vector3.ONE * 0.001)
	assert_vector(_on_client(smooth).position).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)
	assert_float(_on_client(smooth).rotation.y).is_equal_approx(0.0, 0.001)
	# Shown as it is now once the delay is gone.
	_smoothing.delay = 0.0
	await _settle()
	assert_vector(_on_client(smooth).position).is_equal_approx(Vector3(3, 0, 0), Vector3.ONE * 0.001)
	assert_float(_on_client(smooth).rotation.y).is_equal_approx(0.5, 0.001)
	assert_float((_on_client(smooth).get_node("Head") as Node3D).rotation.x).is_equal_approx(0.3, 0.001)


func test_a_teleport_is_not_slid_across() -> void:
	_smoothing.delay = 30.0
	var smooth := _spawn(Vector3.ZERO, true)
	await _settle()
	smooth.position = Vector3(200, 0, 0)
	await _settle()
	assert_vector(_on_client(smooth).position).is_equal_approx(Vector3(200, 0, 0), Vector3.ONE * 0.001)


func test_a_client_write_on_a_still_thing_gives_way_to_the_server() -> void:
	_smoothing.delay = 0.0
	var smooth := _spawn(Vector3.ZERO, true)
	await _settle()
	# Standing still the smoothing writes nothing new, but the next update puts the server's
	# value back.
	_on_client(smooth).position = Vector3(0, 5, 0)
	await _settle()
	assert_vector(_on_client(smooth).position).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)
	_on_client(smooth).position = Vector3(0, 5, 0)
	# A move on the server is shown, smoothed, from wherever the client had it.
	smooth.position = Vector3(3, 0, 0)
	await _settle()
	assert_vector(_on_client(smooth).position).is_equal_approx(Vector3(3, 0, 0), Vector3.ONE * 0.001)


func test_it_lets_go_of_things_that_leave() -> void:
	var smooth := _spawn(Vector3.ZERO, true)
	await _settle()
	assert_int(_smoothing.tracked_count()).is_equal(1)
	var name := String(smooth.name)
	smooth.queue_free()
	await _settle()
	assert_object(_client.get_node_or_null("World/" + name)).is_null()
	assert_int(_smoothing.tracked_count()).is_equal(0)

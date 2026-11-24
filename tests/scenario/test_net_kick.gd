extends GdUnitTestSuite
## A real server and client in one process over ENet, with something replicating to the
## client every frame. A server cutting a peer off must stop sending to it at once: ENet drops
## a peer's channels as soon as a disconnect starts, and every packet sent to it after that
## logged "Unable to send packet on channel 0, max channels: 0" (#552), for as long as the
## peer took to answer. The peer is let go exactly once.


class SendErrors extends Logger:
	var count := 0

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if code.contains("Unable to send packet") or rationale.contains("Unable to send packet"):
			count += 1

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _server: Node
var _client: Node
var _server_peer: ENetMultiplayerPeer
var _client_peer: ENetMultiplayerPeer
var _client_api: SceneMultiplayer
var _net: NetSession
var _errors: SendErrors
var _left: Array[int] = []
var _leaving: Array[int] = []


func _branch(branch_name: String) -> Node:
	var root := Node.new()
	root.name = branch_name
	add_child(root)
	var spawner := MultiplayerSpawner.new()
	spawner.name = "Spawner"
	spawner.spawn_path = NodePath("..")
	spawner.spawn_function = _make
	root.add_child(spawner)
	return root


func _make(_data: Variant) -> Node:
	var thing := Node3D.new()
	thing.name = "Thing"
	thing.add_child(NetSync.make([".:position"]))
	return thing


func before_test() -> void:
	_server = _branch("Server")
	_client = _branch("Client")
	var port := 7990 + randi() % 50
	_server_peer = ENetMultiplayerPeer.new()
	assert_int(_server_peer.create_server(port, 4)).is_equal(OK)
	var server_api := SceneMultiplayer.new()
	server_api.multiplayer_peer = _server_peer
	get_tree().set_multiplayer(server_api, _server.get_path())
	_client_peer = ENetMultiplayerPeer.new()
	assert_int(_client_peer.create_client("127.0.0.1", port)).is_equal(OK)
	_client_api = SceneMultiplayer.new()
	_client_api.multiplayer_peer = _client_peer
	get_tree().set_multiplayer(_client_api, _client.get_path())
	# A session of its own under the server branch, so it talks through the server's API.
	_net = (load("res://core/net.gd") as GDScript).new()
	_net.name = "Net"
	_server.add_child(_net)
	_net.peer_leaving.connect(func(peer: int) -> void: _leaving.append(peer))
	_net.peer_left.connect(func(peer: int) -> void: _left.append(peer))
	for i in 120:
		if _client.multiplayer.get_unique_id() > 1 and _server.multiplayer.get_peers().size() == 1:
			break
		await get_tree().process_frame
	_errors = SendErrors.new()
	OS.add_logger(_errors)


func after_test() -> void:
	OS.remove_logger(_errors)
	# Its synced nodes leave the tree through the API that tracks them.
	get_tree().set_multiplayer(_client_api, _client.get_path())
	var client_path := _client.get_path()
	var server_path := _server.get_path()
	_client.free()
	_server.free()
	_client_peer.close()
	_server_peer.close()
	get_tree().set_multiplayer(null, client_path)
	get_tree().set_multiplayer(null, server_path)


func test_a_cut_peer_is_sent_nothing_more_and_let_go_once() -> void:
	var peer := _server.multiplayer.get_peers()[0]
	_net._identities[peer] = {"name": "Kicked", "key": "test"}
	(_server.get_node("Spawner") as MultiplayerSpawner).spawn(null)
	for i in 10:
		await get_tree().process_frame
	assert_object(_client.get_node_or_null("Thing")).is_not_null()
	# A client too busy to answer (loading its world): nothing polls its end any more.
	get_tree().set_multiplayer(null, _client.get_path())
	_net._cut(peer)
	assert_array(_left).contains_exactly([peer])
	assert_array(_leaving).contains_exactly([peer])
	assert_array(_server.multiplayer.get_peers()).is_empty()
	# Replication keeps running on the server meanwhile.
	for i in 60:
		var thing := _server.get_node("Thing") as Node3D
		thing.position.x += 0.1
		await get_tree().process_frame
	assert_int(_errors.count).is_equal(0)
	assert_array(_left).contains_exactly([peer])

extends GdUnitTestSuite
## A real server and client in one process over ENet: someone climbing a ladder on the server
## is shown climbing on the client, not falling. Their copy there gets the synced `climbing`
## flag, so it does not count as airborne while it rises at climbing speed, and its body
## switches to the climb pose and back once they step off at the bottom.

const PLAYER := "res://modules/player/scenes/player.tscn"
## A ladder against a wall in front of the player (-z), as in test_player_ladder.
const LADDER_TOP := 6.0

var _server: Node
var _client: Node
var _server_peer: ENetMultiplayerPeer
var _client_peer: ENetMultiplayerPeer
var _owner := RefCounted.new()


func _branch(branch_name: String, make: Callable) -> Node:
	var root := Node.new()
	root.name = branch_name
	add_child(root)
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	var spawner := MultiplayerSpawner.new()
	spawner.name = "Spawner"
	spawner.spawn_path = NodePath("..")
	spawner.spawn_function = make
	world.add_child(spawner)
	return root


func _make_server(_data: Variant) -> Node:
	var player: PlayerController = (load(PLAYER) as PackedScene).instantiate()
	player.name = "Climber"
	# Back from the ladder: put down inside its reach, off the ground, a body holds on.
	player.position = Vector3(0, 0.05, 1.5)
	return player


func _make_client(_data: Variant) -> Node:
	var copy: PlayerController = (load(PLAYER) as PackedScene).instantiate()
	copy.name = "Climber"
	PlayerController.hold_still(copy)
	# Both copies share this process's physics space; the server's must not bump into it.
	copy.collision_layer = 0
	var animator := PlayerBodyAnimator.new()
	animator.name = "BodyAnimator"
	animator.player = copy
	copy.add_child(animator)
	return copy


func _box(at: Vector3, size: Vector3) -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	body.collision_layer = PhysicsLayers.SOLID
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = at


func before_test() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	_box(Vector3(0, LADDER_TOP / 2.0, -0.6), Vector3(2.0, LADDER_TOP, 0.2))
	Ladders.add(_owner, Transform3D(Basis.IDENTITY, Vector3(0, LADDER_TOP / 2.0, -0.1)), Vector3(0.4, LADDER_TOP / 2.0, 0.4), Vector3.FORWARD)
	_server = _branch("Server", _make_server)
	_client = _branch("Client", _make_client)
	var port := 8110 + randi() % 60
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


func after_test() -> void:
	Ladders.remove(_owner)
	var client_path := _client.get_path()
	var server_path := _server.get_path()
	_client.free()
	_server.free()
	_client_peer.close()
	_server_peer.close()
	get_tree().set_multiplayer(null, client_path)
	get_tree().set_multiplayer(null, server_path)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func test_a_remote_climber_is_shown_climbing_not_falling() -> void:
	var climber := (_server.get_node("World/Spawner") as MultiplayerSpawner).spawn(null) as PlayerController
	await _frames(10)
	var copy := _client.get_node_or_null("World/Climber") as PlayerController
	assert_object(copy).is_not_null()
	var animator := copy.get_node("BodyAnimator") as PlayerBodyAnimator
	assert_bool(copy.climbing).is_false()

	climber.intent().move = Vector2(0, 1)
	await _frames(60)
	assert_bool(climber.climbing).is_true()
	# Rising faster than a body standing still ever does: by speed alone this is a fall.
	assert_float(copy.velocity.y).is_greater(PlayerController.HELD_AIRBORNE_SPEED)
	assert_bool(copy.climbing).is_true()
	assert_bool(copy.airborne()).is_false()
	assert_float(animator.climb_amount()).is_greater(0.9)
	assert_float(animator.air_amount()).is_less(0.1)

	# Down again and off at the bottom: the copy lets go and the pose goes back.
	climber.intent().move = Vector2(0, -1)
	for i in 240:
		await get_tree().physics_frame
		if not climber.climbing and climber.is_on_floor():
			break
	climber.intent().move = Vector2.ZERO
	await _frames(30)
	assert_bool(climber.climbing).is_false()
	assert_bool(copy.climbing).is_false()
	assert_float(animator.climb_amount()).is_less(0.1)
	assert_float(animator.air_amount()).is_less(0.1)


func test_hands_take_turns_on_the_rails() -> void:
	# Each hand holds for part of the cycle while the other reaches up past it.
	var grips := PlayerBodyAnimator.rail_grips(0.0)
	var later := PlayerBodyAnimator.rail_grips(0.25)
	var right_rise := (later[&"R"] as Vector3).y - (grips[&"R"] as Vector3).y
	var left_rise := (later[&"L"] as Vector3).y - (grips[&"L"] as Vector3).y
	assert_float(right_rise * left_rise).is_less(0.0)
	assert_float((grips[&"R"] as Vector3).x).is_greater(0.0)
	assert_float((grips[&"L"] as Vector3).x).is_less(0.0)

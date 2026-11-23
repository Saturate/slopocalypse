extends GdUnitTestSuite
## A client builds its ground round its camera, and a headless client (playtests run with
## --headless, bots, net tests) has none. It followed only the camp then, so its own player
## far from it stood where nothing was built (partner-marker --headless never saw the city
## ready). Without a camera, a client follows its own player.

const WORLD := "res://modules/world/scenes/world.tscn"

var _world: Node3D
var _voxels: VoxelWorld
var _peer: ENetMultiplayerPeer


func before_test() -> void:
	_world = await VoxelWorld.add_and_wait(self, WORLD)
	_voxels = _world.get_node("Terrain")
	# A client of a server that is not there: it has a peer, its own id and is not the server,
	# which is all the world asks.
	_peer = ENetMultiplayerPeer.new()
	assert_int(_peer.create_client("127.0.0.1", 9)).is_equal(OK)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = _peer
	get_tree().set_multiplayer(api, _world.get_path())


func after_test() -> void:
	get_tree().set_multiplayer(null, _world.get_path())
	_peer.close()
	_world.free()


func _player(peer: int, at: Vector3) -> Node3D:
	var n: Node3D = auto_free(Node3D.new())
	n.add_to_group(&"players")
	n.set_meta(&"peer_id", peer)
	add_child(n)
	n.global_position = at
	return n


## Two opposite corners of the map, well inside its edge and far from the camp.
func _corners() -> Array[Vector3]:
	var area := _voxels.heights.extent().grow(-150.0)
	return [Vector3(area.position.x, 0, area.position.y), Vector3(area.end.x, 0, area.end.y)]


func test_a_client_without_a_camera_builds_ground_round_its_own_player_only() -> void:
	assert_object(get_viewport().get_camera_3d()).is_null()
	var me := _world.multiplayer.get_unique_id()
	assert_bool(_world.multiplayer.is_server()).is_false()
	var corners := _corners()
	_player(me, corners[0])
	_player(me + 1, corners[1])
	# The peer never connects and drops its id when ENet gives up (seconds in): wait only
	# until the ground is there.
	for i in 600:
		if _voxels.is_ready_at(corners[0]):
			break
		await get_tree().process_frame
	assert_bool(_voxels.is_ready_at(corners[0])).override_failure_message("no ground under the client's own player").is_true()
	# Someone else's player is the server's business, as with a camera.
	assert_bool(_voxels.is_ready_at(corners[1])).is_false()


## Stands in for the car module: its own player sits in a car parked at `spot`.
class Cars extends Node:
	var driver: Node3D
	var spot: Vector3

	func car_spot_of(player: Node3D) -> Variant:
		return spot if player == driver else null


func test_a_client_without_a_camera_follows_the_car_its_own_player_drives() -> void:
	var corners := _corners()
	# A seated body stays parked where it got in; the car has driven to the other corner.
	var cars: Cars = auto_free(Cars.new())
	cars.add_to_group(&"cars_api")
	cars.driver = _player(_world.multiplayer.get_unique_id(), corners[0])
	cars.spot = corners[1]
	add_child(cars)
	var until := Time.get_ticks_msec() + 10000
	while not _voxels.is_ready_at(corners[1]) and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	assert_bool(_voxels.is_ready_at(corners[1])).override_failure_message("no ground under the car the client drives").is_true()
	assert_bool(_voxels.is_ready_at(corners[0])).override_failure_message("ground built round the parked body").is_false()

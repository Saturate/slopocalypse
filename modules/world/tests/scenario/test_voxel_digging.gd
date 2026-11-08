extends GdUnitTestSuite
## The voxel terrain is solid where the height function says, and digging removes it.

const WORLD := "res://modules/world/scenes/world.tscn"

var _world: Node3D
var _voxels: VoxelWorld


func before_test() -> void:
	_world = (load(WORLD) as PackedScene).instantiate()
	add_child(_world)
	_voxels = _world.get_node("Terrain")
	for i in 900:
		if _voxels.is_ready_at(Vector3.ZERO):
			break
		await get_tree().physics_frame


func after_test() -> void:
	_world.free()


func _sdf(at: Vector3) -> float:
	var tool := _voxels.terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_SDF
	return tool.get_voxel_f(at)


func test_spawn_area_loads() -> void:
	assert_bool(_voxels.is_ready_at(Vector3.ZERO)).is_true()


func test_ground_is_solid_below_and_air_above() -> void:
	assert_float(_sdf(Vector3(0, -2, 0))).is_less(0.0)
	assert_float(_sdf(Vector3(0, 2, 0))).is_greater(0.0)


func test_digging_turns_solid_ground_into_air() -> void:
	var spot := Vector3(3, -1, 3)
	assert_float(_sdf(spot)).is_less(0.0)
	_voxels.server_dig(spot, 2.0)
	assert_float(_sdf(spot)).is_greater(0.0)


func test_players_standing_on_the_terrain_do_not_fall_through() -> void:
	var player: PlayerController = auto_free((load("res://modules/player/scenes/player.tscn") as PackedScene).instantiate())
	add_child(player)
	player.global_position = Vector3(0, 2, 0)
	for i in 120:
		await get_tree().physics_frame
	assert_bool(player.is_on_floor()).is_true()
	assert_float(player.global_position.y).is_equal_approx(0.0, 0.3)


func test_digging_stops_at_the_deepest_a_crater_may_go() -> void:
	var spot := Vector3(-3, 0, 3)
	var deepest := _voxels.ground_height(spot.x, spot.z) - _voxels.max_dig_depth
	for i in 8:
		_voxels.server_dig(spot + Vector3.DOWN * float(i) * 2.0, 2.0)
	assert_float(_sdf(Vector3(spot.x, deepest + 1.0, spot.z))).is_greater(0.0)
	assert_float(_sdf(Vector3(spot.x, deepest - 1.0, spot.z))).is_less(0.0)


func test_a_dig_says_where_the_hole_went() -> void:
	var holes: Array[Vector3] = []
	_voxels.dug.connect(func(center: Vector3, _radius: float) -> void: holes.append(center))
	_voxels.server_dig(Vector3(4, -50, 4), 1.0)
	assert_int(holes.size()).is_equal(1)
	assert_float(holes[0].y).is_equal_approx(_voxels.ground_height(4, 4) - _voxels.max_dig_depth + 1.0, 0.01)

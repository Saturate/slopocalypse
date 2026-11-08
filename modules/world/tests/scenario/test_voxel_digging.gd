extends GdUnitTestSuite
## The ground is solid where the height function says, digging lowers it (never deeper than
## a crater may go), and the collision follows.

const WORLD := "res://modules/world/scenes/world.tscn"

## Open ground down the road from the start tunnel (rays at the spawn would hit its roof).
const OUT := Vector3(0, 0, -40)

var _world: Node3D
var _voxels: VoxelWorld


func before_test() -> void:
	_world = await VoxelWorld.add_and_wait(self, WORLD)
	_voxels = _world.get_node("Terrain")


func after_test() -> void:
	_world.free()


func _ray_down(at: Vector3) -> float:
	var space := get_viewport().find_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 30.0, at + Vector3.DOWN * 30.0))
	return (hit["position"] as Vector3).y if not hit.is_empty() else -INF


func test_spawn_area_loads() -> void:
	assert_bool(_voxels.is_ready_at(Vector3.ZERO)).is_true()


func test_collision_matches_the_ground() -> void:
	await get_tree().physics_frame
	for at in [OUT + Vector3(3, 0, 3), OUT + Vector3(-10, 0, 6), OUT + Vector3(12, 0, -12)]:
		assert_float(_ray_down(at)).is_equal_approx(_voxels.ground_height(at.x, at.z), 0.05)


func test_digging_lowers_the_ground_and_its_collision() -> void:
	var spot := OUT + Vector3(3, 0, 3)
	var before := _voxels.surface_height(spot.x, spot.z)
	_voxels.server_dig(spot, 2.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_float(_voxels.surface_height(spot.x, spot.z)).is_less(before - 1.0)
	assert_float(_ray_down(spot)).is_equal_approx(_voxels.surface_height(spot.x, spot.z), 0.1)


func test_digging_stops_at_the_deepest_a_crater_may_go() -> void:
	var spot := OUT + Vector3(-3, 0, 3)
	var deepest := _voxels.ground_height(spot.x, spot.z) - _voxels.max_dig_depth
	for i in 8:
		_voxels.server_dig(spot + Vector3.DOWN * float(i) * 2.0, 2.0)
	assert_float(_voxels.surface_height(spot.x, spot.z)).is_greater_equal(deepest - 0.01)


func test_a_dig_says_where_the_hole_went() -> void:
	var holes: Array[Vector3] = []
	_voxels.dug.connect(func(center: Vector3, _radius: float) -> void: holes.append(center))
	_voxels.server_dig(OUT + Vector3(4, -50, 4), 1.0)
	assert_int(holes.size()).is_equal(1)
	assert_float(holes[0].y).is_equal_approx(_voxels.ground_height(OUT.x + 4, OUT.z + 4) - _voxels.max_dig_depth + 1.0, 0.01)


func test_players_standing_on_the_terrain_do_not_fall_through() -> void:
	var player: PlayerController = auto_free((load("res://modules/player/scenes/player.tscn") as PackedScene).instantiate())
	add_child(player)
	player.global_position = Vector3(0, 2, 0)
	for i in 120:
		await get_tree().physics_frame
	assert_bool(player.is_on_floor()).is_true()
	assert_float(player.global_position.y).is_equal_approx(0.0, 0.3)

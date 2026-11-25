extends GdUnitTestSuite
## The ground is solid where the height function says, digging lowers it (never deeper than
## a crater may go), and the collision follows.

const WORLD := "res://modules/world/scenes/world.tscn"

## Metres of open ground round `_out`: no road (pads keep off roads) and no pond.
const OPEN_REACH := 50.0

## Open ground near the camp, kept built for the test.
var _out := Vector3.ZERO
var _world: Node3D
var _voxels: VoxelWorld


func before_test() -> void:
	_world = await VoxelWorld.add_and_wait(self, WORLD)
	_voxels = _world.get_node("Terrain")
	_out = _open_ground()
	var viewer := _voxels.make_viewer()
	_world.add_child(viewer)
	viewer.global_position = _out
	_voxels.update_around([_out], INF)


## The nearest spot to the camp, on rings 40 m apart, with OPEN_REACH metres of open ground
## round it.
func _open_ground() -> Vector3:
	var shape := _voxels.heights
	var home := _voxels.home
	for ring in range(1, 20):
		for k in 16:
			var angle := TAU * k / 16.0
			var at := home + Vector3(cos(angle), 0, sin(angle)) * ring * 40.0
			if _is_open(shape, at):
				return Vector3(at.x, 0, at.z)
	fail("no open ground near the camp")
	return home


func _is_open(shape: GroundShape, at: Vector3) -> bool:
	if shape.near_road(at.x, at.z, OPEN_REACH):
		return false
	for dx in range(-5, 6):
		for dz in range(-5, 6):
			var x := at.x + dx * OPEN_REACH / 5.0
			var z := at.z + dz * OPEN_REACH / 5.0
			if shape.in_water(x, z) or shape.near_road(x, z, 4.0) or shape.on_site(x, z):
				return false
	return true


func after_test() -> void:
	_world.free()


func _ray_down(at: Vector3) -> float:
	var space := get_viewport().find_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 30.0, at + Vector3.DOWN * 30.0))
	return (hit["position"] as Vector3).y if not hit.is_empty() else -INF


func test_spawn_area_loads() -> void:
	assert_bool(_voxels.is_ready_at(_voxels.home)).is_true()


func test_collision_matches_the_ground() -> void:
	await get_tree().physics_frame
	for at in [_out + Vector3(3, 0, 3), _out + Vector3(-10, 0, 6), _out + Vector3(12, 0, -12)]:
		assert_float(_ray_down(at)).is_equal_approx(_voxels.ground_height(at.x, at.z), 0.05)


func test_digging_lowers_the_ground_and_its_collision() -> void:
	var spot := _out + Vector3(3, 0, 3)
	var before := _voxels.surface_height(spot.x, spot.z)
	spot.y = before
	_voxels.server_dig(spot, 2.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_float(_voxels.surface_height(spot.x, spot.z)).is_less(before - 2.0 * _voxels.crater_depth_share * 0.9)
	assert_float(_ray_down(spot)).is_equal_approx(_voxels.surface_height(spot.x, spot.z), 0.1)


func test_a_crater_keeps_its_size_and_its_walls_are_walkable() -> void:
	# The biggest blast in the game, on open ground.
	var spot := _out + Vector3(-12, 0, -8)
	var radius := 4.0
	var before := _voxels.surface_height(spot.x, spot.z)
	spot.y = before
	_voxels.server_dig(spot, radius)
	# As wide as before: the ground is lowered most of the way out to the radius.
	var near_rim := spot + Vector3(radius * 0.8, 0, 0)
	assert_float(_voxels.surface_height(near_rim.x, near_rim.z)).is_less(_voxels.ground_height(near_rim.x, near_rim.z) - 0.05)
	assert_float(_voxels.surface_height(spot.x, spot.z)).is_less(before - radius * 0.3)
	_assert_walkable(spot, radius)


func test_blasting_the_same_crater_again_keeps_it_walkable() -> void:
	var spot := _out + Vector3(14, 0, -6)
	var radius := 4.0
	var before := _voxels.surface_height(spot.x, spot.z)
	for i in 4:
		# Each blast on the floor the last one left, a little off centre as in a firefight.
		var at := spot + Vector3(0.6 * float(i), 0, -0.4 * float(i))
		at.y = _voxels.surface_height(at.x, at.z)
		_voxels.server_dig(at, radius)
	assert_float(_voxels.surface_height(spot.x, spot.z)).is_greater_equal(before - radius * _voxels.crater_depth_share - 0.01)
	_assert_walkable(spot, radius + 2.0)


func test_a_blast_in_the_air_dents_less_and_high_enough_not_at_all() -> void:
	var spot := _out + Vector3(-6, 0, 10)
	var radius := 2.0
	var most := radius * _voxels.crater_depth_share
	var before := _voxels.surface_height(spot.x, spot.z)
	_voxels.server_dig(spot + Vector3.UP * (before - spot.y + most * 0.5), radius)
	assert_float(_voxels.surface_height(spot.x, spot.z)).is_equal_approx(before - most * 0.5, 0.01)
	var far := _out + Vector3(8, 0, 12)
	var untouched := _voxels.surface_height(far.x, far.z)
	_voxels.server_dig(Vector3(far.x, untouched + most + 0.1, far.z), radius)
	assert_float(_voxels.surface_height(far.x, far.z)).is_equal(untouched)
	assert_int(_voxels.dig_log().size()).is_equal(1)


func test_digging_stops_at_the_deepest_a_crater_may_go() -> void:
	# Wide enough that its share of the radius would go deeper than the cap.
	var spot := _out + Vector3(-3, 0, 3)
	spot.y = _voxels.ground_height(spot.x, spot.z)
	var radius := _voxels.max_dig_depth / _voxels.crater_depth_share + 2.0
	var deepest := _voxels.ground_height(spot.x, spot.z) - _voxels.max_dig_depth
	for i in 4:
		_voxels.server_dig(spot + Vector3.DOWN * float(i) * 2.0, radius)
	assert_float(_voxels.surface_height(spot.x, spot.z)).is_equal_approx(deepest, 0.01)


func test_ground_levelled_by_one_owner_is_claimed_for_everyone_else() -> void:
	var at := _out + Vector3(30, 0, 0)
	_voxels.set_pads_for(&"city", [{"at": at, "half": Vector2(20, 10), "yaw": PI / 2.0, "blend": 6.0}])
	# Turned a quarter: 10 m across x, 20 m along z, and its blend round that.
	assert_bool(_voxels.is_claimed(at + Vector3(0, 0, 18), 1.0, &"")).is_true()
	assert_bool(_voxels.is_claimed(at + Vector3(14, 0, 0), 1.0, &"")).is_true()
	assert_bool(_voxels.is_claimed(at + Vector3(20, 0, 0), 1.0, &"")).is_false()
	assert_bool(_voxels.is_claimed(at + Vector3(19, 0, 0), 4.0, &"")).is_true()
	# Its own pads never block the owner, which replaces them.
	assert_bool(_voxels.is_claimed(at, 1.0, &"city")).is_false()


func test_a_map_sites_pad_is_claimed_for_everyone() -> void:
	var sites := _voxels.map_site_list()
	assert_int(sites.size()).is_greater(0)
	for site in sites:
		var foot: Rect2 = site["footprint"]
		var centre: Vector3 = site["centre"]
		# Missions put nothing on a farm, mast or tower, nor just off its edge.
		assert_bool(_voxels.is_claimed(centre, 1.0, &"")).is_true()
		assert_bool(_voxels.is_claimed(centre, 1.0, &"city")).is_true()
		var edge := Vector3(foot.end.x + 2.0, centre.y, centre.z)
		assert_bool(_voxels.is_claimed(edge, 3.0, &"")).is_true()


func test_a_pad_can_slope_from_one_end_to_the_other() -> void:
	# A ramp 20 m long along z (yaw 0): 2 m up at -z, level with 0 at +z.
	var at := _out + Vector3(-30, 0, 0)
	_voxels.set_pads_for(&"ramp", [{"at": at, "half": Vector2(4, 10), "yaw": 0.0, "blend": 3.0, "from": at.y + 2.0}])
	assert_float(_voxels.surface_height(at.x, at.z - 10.0)).is_equal_approx(at.y + 2.0, 0.01)
	assert_float(_voxels.surface_height(at.x, at.z)).is_equal_approx(at.y + 1.0, 0.01)
	assert_float(_voxels.surface_height(at.x, at.z + 10.0)).is_equal_approx(at.y, 0.01)


func test_a_crater_on_a_pad_replays_as_deep_without_the_pad() -> void:
	# A levelled pad 2 m over the ground, as under a mission building on a slope.
	var spot := _out + Vector3(10, 0, 8)
	var ground := _voxels.ground_height(spot.x, spot.z)
	_voxels.set_pads_for(&"test", [{"at": Vector3(spot.x, ground + 2.0, spot.z), "half": Vector2(6, 6), "yaw": 0.0, "blend": 3.0}])
	var on_pad := _voxels.surface_height(spot.x, spot.z)
	_voxels.server_dig(Vector3(spot.x, on_pad, spot.z), 2.0)
	var depth := on_pad - _voxels.surface_height(spot.x, spot.z)
	assert_float(depth).is_equal_approx(2.0 * _voxels.crater_depth_share, 0.01)
	# A late joiner replays the log before its pads are set: the entry gives the same depth
	# against the bare ground alone, which every instance agrees on.
	var logged: Vector4 = _voxels.dig_log()[0]
	var most := 2.0 * _voxels.crater_depth_share
	assert_float(most - (logged.y - ground)).is_equal_approx(depth, 0.01)
	_voxels.set_pads_for(&"test", [])
	_voxels.replay_dig(logged)
	assert_float(ground - _voxels.surface_height(spot.x, spot.z)).is_equal_approx(depth, 0.01)


func test_a_dig_says_where_the_hole_went() -> void:
	var holes: Array[Vector3] = []
	_voxels.dug.connect(func(center: Vector3, _radius: float) -> void: holes.append(center))
	var at := _out + Vector3(4, -50, 4)
	var before := _voxels.surface_height(at.x, at.z)
	# Deep under the ground counts as on it: no deeper than one bowl.
	_voxels.server_dig(at, 1.0)
	assert_int(holes.size()).is_equal(1)
	assert_float(holes[0].y).is_equal_approx(before, 0.01)
	assert_float(_voxels.surface_height(at.x, at.z)).is_equal_approx(before - _voxels.crater_depth_share, 0.01)


## Walking across `spot` every 0.1 m in three directions, no step climbs steeper than a
## player walks up (CharacterBody3D's 45 degrees); the crater's own share stays under 42.
func _assert_walkable(spot: Vector3, reach: float) -> void:
	var step := 0.1
	for angle in [0.0, PI / 4.0, PI / 2.0]:
		var dir := Vector3(cos(angle), 0, sin(angle))
		var x := -reach * 1.2
		while x < reach * 1.2:
			var a := spot + dir * x
			var b := spot + dir * (x + step)
			var rise := absf(_voxels.surface_height(b.x, b.z) - _voxels.surface_height(a.x, a.z)) / step
			var ground := absf(_voxels.ground_height(b.x, b.z) - _voxels.ground_height(a.x, a.z)) / step
			var where := "%.2f m out at %.2f rad" % [x, angle]
			assert_float(rise).override_failure_message("too steep to walk " + where).is_less_equal(1.0)
			assert_float(rise - ground).override_failure_message("crater too steep " + where).is_less_equal(tan(deg_to_rad(42.0)))
			x += step


func test_players_standing_on_the_terrain_do_not_fall_through() -> void:
	var player: PlayerController = auto_free((load("res://modules/player/scenes/player.tscn") as PackedScene).instantiate())
	add_child(player)
	var ground := _voxels.surface_height(_out.x, _out.z)
	player.global_position = Vector3(_out.x, ground + 2.0, _out.z)
	for i in 120:
		await get_tree().physics_frame
	assert_bool(player.is_on_floor()).is_true()
	assert_float(player.global_position.y).is_equal_approx(ground, 0.3)


func test_a_pad_levels_the_ground_under_it_and_eases_back_into_the_slope() -> void:
	var centre := _out + Vector3(14, 0, -6)
	var level := _voxels.ground_height(centre.x, centre.z) + 0.7
	# Nothing growing on it, as missions and the city clear theirs: the rays below are for the
	# ground, not a tree or rock that happens to stand there.
	for scenery: Node in get_tree().get_nodes_in_group(&"scenery"):
		scenery.call(&"set_clearings_for", &"test_pad", [{"at": centre, "radius": 12.0}])
	# Turned a quarter: its 6 m length runs along z.
	_voxels.set_pads([{"at": Vector3(centre.x, level, centre.z), "half": Vector2(6.0, 3.0), "yaw": PI / 2.0, "blend": 3.0}])
	await get_tree().physics_frame
	await get_tree().physics_frame
	for offset: Vector3 in [Vector3.ZERO, Vector3(2.5, 0, 5.5), Vector3(-2.5, 0, -5.5)]:
		var at := centre + offset
		assert_float(_voxels.surface_height(at.x, at.z)).override_failure_message("inside at %s" % offset).is_equal_approx(level, 0.001)
		assert_float(_ray_down(at)).override_failure_message("collision at %s" % offset).is_equal_approx(level, 0.1)
	# Past the blend it's the natural ground again.
	var far := centre + Vector3(7.0, 0, 0)
	assert_float(_voxels.surface_height(far.x, far.z)).is_equal_approx(_voxels.ground_height(far.x, far.z), 0.001)
	# Clearing the pads gives the slope back.
	_voxels.set_pads([])
	assert_float(_voxels.surface_height(centre.x, centre.z)).is_equal_approx(_voxels.ground_height(centre.x, centre.z), 0.001)

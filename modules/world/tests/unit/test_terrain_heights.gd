extends GdUnitTestSuite

const CONFIG := "res://modules/world/data/world.json"

var _heights: TerrainHeights


func before_test() -> void:
	var data: Dictionary = Data.load_json(CONFIG)
	_heights = TerrainHeights.new(data)


func test_config_has_every_required_field() -> void:
	var data: Dictionary = Data.load_json(CONFIG)
	assert_bool(Data.require(CONFIG, data, TerrainHeights.REQUIRED)).is_true()


func test_same_input_gives_same_height() -> void:
	assert_float(_heights.height_at(40.0, -33.0)).is_equal(_heights.height_at(40.0, -33.0))


func test_the_spawn_is_on_the_road_inside_the_start_tunnel() -> void:
	assert_bool(_heights.in_tunnel(0.0, 0.0)).is_true()
	assert_float(_heights.road.distance(0.0, 0.0)).is_less(_heights.road.half_width)
	assert_float(_heights.height_at(0.0, 0.0)).is_equal_approx(_heights.road.height_at(0.0), 0.001)


func test_the_tunnel_floor_is_the_road_from_wall_to_wall() -> void:
	var half: float = _heights.start["tunnel_half_width"]
	for z in [float(_heights.start["portal_z"]) + 0.5, 0.0, float(_heights.start["tunnel_end_z"]) - 0.5]:
		for x in [-half + 0.1, 0.0, half - 0.1]:
			assert_float(_heights.height_at(x, z)).is_equal_approx(_heights.road.height_at(z), 0.001)


func test_the_mountain_stands_over_the_tunnel_and_beside_it() -> void:
	var half: float = _heights.start["tunnel_half_width"]
	var tall := float(_heights.start["tunnel_height"]) + 2.0
	for z in [float(_heights.start["portal_z"]) + 2.0, 0.0, 10.0]:
		var floor_y := _heights.road.height_at(z)
		assert_float(_heights.natural_height(0.0, z) - floor_y).is_greater(tall)
		assert_float(_heights.height_at(half + 3.0, z) - floor_y).is_greater(tall)
		assert_float(_heights.height_at(-half - 3.0, z) - floor_y).is_greater(tall)


func test_the_road_comes_out_of_the_portal_into_the_open() -> void:
	var z := float(_heights.start["portal_z"]) - 3.0
	assert_float(_heights.height_at(0.0, z)).is_equal_approx(_heights.road.height_at(z), 0.01)
	assert_float(_heights.mountain_height(0.0, z - 40.0)).is_equal(0.0)


func test_there_is_no_road_behind_the_cave_in() -> void:
	var end: float = _heights.start["tunnel_end_z"]
	assert_float(_heights.road.z_start()).is_equal_approx(end, 0.001)
	assert_float(_heights.road.distance(0.0, end + 5.0)).is_equal(INF)
	assert_bool(_heights.in_tunnel(0.0, end + 5.0)).is_false()


func test_the_road_runs_straight_out_of_the_tunnel() -> void:
	for z in [0.0, float(_heights.start["portal_z"]), -RoadPath.STRAIGHT]:
		assert_float(_heights.road.x_at(z)).is_equal_approx(0.0, 0.001)


func test_without_a_start_block_there_is_no_mountain() -> void:
	var data: Dictionary = Data.load_json(CONFIG)
	data.erase("start")
	var plain := TerrainHeights.new(data)
	assert_bool(plain.has_tunnel()).is_false()
	assert_float(plain.mountain_height(0.0, 30.0)).is_equal(0.0)
	assert_float(plain.road.z_start()).is_equal_approx(plain.z_max(), 0.001)


func test_terrain_has_relief_away_from_spawn() -> void:
	var lowest := INF
	var highest := -INF
	for i in 50:
		var h := _heights.height_at(60.0 + i * 3.0, -70.0 + i * 2.0)
		lowest = minf(lowest, h)
		highest = maxf(highest, h)
	assert_float(highest - lowest).is_greater(2.0)


func test_the_world_is_a_long_strip_down_the_road() -> void:
	var area := _heights.extent()
	assert_float(area.size.y).is_greater(area.size.x * 4.0)
	assert_bool(area.has_point(Vector2(0.0, 0.0))).is_true()
	assert_float(area.end.y).is_equal_approx(_heights.behind, 0.001)


func test_the_road_runs_the_whole_length() -> void:
	assert_object(_heights.road).is_not_null()
	for z in [_heights.road.z_start(), 0.0, -1000.0, _heights.z_min()]:
		var x := _heights.road.x_at(z)
		assert_float(x).is_between(_heights.extent().position.x + 10.0, _heights.extent().end.x - 10.0)


func test_the_ground_under_the_road_is_level_with_it() -> void:
	for z in [-100.0, -700.0, -1800.0, -2600.0]:
		var x := _heights.road.x_at(z)
		assert_float(_heights.height_at(x, z)).is_equal_approx(_heights.road.height_at(z), 0.01)
		assert_float(_heights.height_at(x + _heights.road.half_width - 0.5, z)).is_equal_approx(_heights.road.height_at(z), 0.01)


func test_the_road_never_has_a_step() -> void:
	var worst := 0.0
	var z := _heights.road.z_start()
	while z > _heights.z_min() + 1.0:
		worst = maxf(worst, absf(_heights.road.height_at(z - 1.0) - _heights.road.height_at(z)))
		z -= 1.0
	var data: Dictionary = Data.load_json(CONFIG)
	assert_float(worst).is_less_equal(float(data["road"]["max_grade"]) + 0.001)


func test_stages_interpolate_between_neighbours() -> void:
	var stages := RoadStages.new([{"at": 0.0, "hills": 1.0}, {"at": 100.0, "hills": 3.0}])
	assert_float(stages.value("hills", -5.0)).is_equal(1.0)
	assert_float(stages.value("hills", 50.0)).is_equal_approx(2.0, 0.001)
	assert_float(stages.value("hills", 500.0)).is_equal(3.0)
	assert_float(stages.value("missing", 50.0, 7.0)).is_equal(7.0)

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


func test_spawn_area_is_flat() -> void:
	assert_float(_heights.height_at(0.0, 0.0)).is_equal_approx(0.0, 0.001)
	assert_float(_heights.height_at(5.0, -5.0)).is_equal_approx(0.0, 0.001)


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
	for z in [_heights.z_max(), 0.0, -1000.0, _heights.z_min()]:
		var x := _heights.road.x_at(z)
		assert_float(x).is_between(_heights.extent().position.x + 10.0, _heights.extent().end.x - 10.0)


func test_the_ground_under_the_road_is_level_with_it() -> void:
	for z in [-100.0, -700.0, -1800.0, -2600.0]:
		var x := _heights.road.x_at(z)
		assert_float(_heights.height_at(x, z)).is_equal_approx(_heights.road.height_at(z), 0.01)
		assert_float(_heights.height_at(x + _heights.road.half_width - 0.5, z)).is_equal_approx(_heights.road.height_at(z), 0.01)


func test_the_road_never_has_a_step() -> void:
	var worst := 0.0
	var z := _heights.z_max()
	while z > _heights.z_min() + 1.0:
		worst = maxf(worst, absf(_heights.road.height_at(z - 1.0) - _heights.road.height_at(z)))
		z -= 1.0
	var data: Dictionary = Data.load_json(CONFIG)
	assert_float(worst).is_less_equal(float(data["road"]["max_grade"]) + 0.001)


func test_the_road_stays_clear_of_the_spawn() -> void:
	assert_float(_heights.road.distance(0.0, 0.0)).is_greater(_heights.road.half_width + 4.0)


func test_stages_interpolate_between_neighbours() -> void:
	var stages := RoadStages.new([{"at": 0.0, "hills": 1.0}, {"at": 100.0, "hills": 3.0}])
	assert_float(stages.value("hills", -5.0)).is_equal(1.0)
	assert_float(stages.value("hills", 50.0)).is_equal_approx(2.0, 0.001)
	assert_float(stages.value("hills", 500.0)).is_equal(3.0)
	assert_float(stages.value("missing", 50.0, 7.0)).is_equal(7.0)

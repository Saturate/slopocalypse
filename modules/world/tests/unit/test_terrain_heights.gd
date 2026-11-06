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


func test_spacing_matches_size_and_resolution() -> void:
	assert_float(_heights.spacing()).is_equal_approx(2.0, 0.0001)

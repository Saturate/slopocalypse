extends GdUnitTestSuite
## The biome noise fields WorldLand shapes by the land.

const CONFIG := {"seed": 77.0, "forest_frequency": 0.012, "forest_threshold": 0.52, "dry_frequency": 0.01, "rock_frequency": 0.018, "rock_threshold": 0.66}

var _biomes: Biomes


func before_test() -> void:
	_biomes = Biomes.new(CONFIG)


func test_same_seed_same_biome() -> void:
	var other := Biomes.new(CONFIG)
	assert_float(other.forest(37.0, -81.0)).is_equal(_biomes.forest(37.0, -81.0))


func test_fields_stay_in_range() -> void:
	for i in 200:
		var x := -120.0 + float(i) * 1.2
		var z := 90.0 - float(i) * 0.9
		for v: float in [_biomes.forest(x, z), _biomes.dry(x, z), _biomes.rock(x, z)]:
			assert_float(v).is_between(0.0, 1.0)


func test_map_has_both_forest_and_open_ground() -> void:
	var forested := 0
	var open := 0
	for gx in 20:
		for gz in 20:
			var f := _biomes.forest(-120.0 + gx * 12.0, -120.0 + gz * 12.0)
			if f > 0.8:
				forested += 1
			elif f < 0.2:
				open += 1
	# Neither a solid forest nor a bare field: both biomes take a real share of the map.
	assert_int(forested).is_greater(40)
	assert_int(open).is_greater(40)


func test_forests_are_never_dry() -> void:
	for i in 100:
		var x := -100.0 + i * 2.0
		if _biomes.forest(x, 10.0) > 0.99:
			assert_float(_biomes.dry(x, 10.0)).is_less(0.02)


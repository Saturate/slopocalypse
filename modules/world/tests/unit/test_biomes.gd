extends GdUnitTestSuite

const CONFIG := "res://modules/world/data/world.json"

var _biomes: Biomes


func before_test() -> void:
	var data: Dictionary = Data.load_json(CONFIG)
	_biomes = Biomes.new(data["biomes"])


func test_config_has_every_required_field() -> void:
	var data: Dictionary = Data.load_json(CONFIG)
	assert_bool(Data.require(CONFIG, data["biomes"], Biomes.REQUIRED)).is_true()


func test_same_seed_same_biome() -> void:
	var data: Dictionary = Data.load_json(CONFIG)
	var other := Biomes.new(data["biomes"])
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


func test_bake_covers_the_area_at_its_resolution() -> void:
	var tex := _biomes.bake(Rect2(-64.0, -256.0, 128.0, 256.0), 4.0)
	assert_int(tex.get_width()).is_equal(32)
	assert_int(tex.get_height()).is_equal(64)


func test_stages_move_the_biomes_down_the_road() -> void:
	var data: Dictionary = Data.load_json(CONFIG)
	var staged := Biomes.new(data["biomes"], RoadStages.new([{"at": 0.0, "forest": 1.0, "dry": 0.0}, {"at": 1000.0, "forest": 0.0, "dry": 1.0}]))
	var early_forest := 0.0
	var late_forest := 0.0
	var late_dry := 0.0
	for i in 200:
		var x := -100.0 + i
		early_forest += staged.forest(x, -10.0)
		late_forest += staged.forest(x, -1500.0)
		late_dry += staged.dry(x, -1500.0)
	assert_float(early_forest).is_greater(late_forest + 20.0)
	assert_float(late_dry).is_greater(100.0)

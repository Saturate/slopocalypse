extends GdUnitTestSuite
## Water collects in the land's low ground (#427): ponds sit in real basins, below their rim,
## and most maps have some.

const GRASSLAND := "res://modules/world/data/maps/grassland.json"


func _recipe() -> Dictionary:
	return Data.load_json(GRASSLAND)


func test_most_maps_have_ponds() -> void:
	var with_water := 0
	for seed_value in 20:
		if not WorldLand.new(_recipe(), seed_value).ponds().is_empty():
			with_water += 1
	assert_int(with_water).is_greater_equal(14)


func test_a_pond_sits_below_every_bank_round_it() -> void:
	var recipe := _recipe()
	for seed_value in 10:
		var land := WorldLand.new(recipe, seed_value)
		for pond: Dictionary in land.ponds():
			var level := float(pond["level"])
			# Walking out from the pond's middle in eight directions, the ground rises above
			# the water before the map ends: nothing spills.
			var centre: Vector2 = pond["centre"]
			for k in 8:
				var dir := Vector2.from_angle(TAU * k / 8.0)
				var rose := false
				var r := 0.0
				while r < 1200.0 and not rose:
					var p := centre + dir * r
					if not land.bounds().has_point(p):
						break
					rose = land.height(p.x, p.y) > level
					r += 8.0
				assert_bool(rose).override_failure_message("seed %d: pond at %s spills to the %s" % [seed_value, centre, dir]).is_true()


func test_water_is_where_the_ground_is_under_a_ponds_level() -> void:
	var recipe := _recipe()
	for seed_value in 10:
		var land := WorldLand.new(recipe, seed_value)
		for pond: Dictionary in land.ponds():
			var centre: Vector2 = pond["centre"]
			var level := land.water_level(centre.x, centre.y)
			assert_float(level).is_equal_approx(float(pond["level"]), 0.01)
			assert_float(land.height(centre.x, centre.y)).is_less(level)
	# Far up a hill there is none.
	var land := WorldLand.new(recipe, 3)
	var b := land.bounds()
	var top := Vector2.ZERO
	var best := -INF
	for i in 32:
		for j in 32:
			var p := b.position + b.size * Vector2(i, j) / 32.0
			if land.height(p.x, p.y) > best:
				best = land.height(p.x, p.y)
				top = p
	assert_bool(is_nan(land.water_level(top.x, top.y))).is_true()


func test_ponds_stay_a_sensible_size() -> void:
	var recipe := _recipe()
	var water: Dictionary = recipe["water"]
	for seed_value in 20:
		for pond: Dictionary in WorldLand.new(recipe, seed_value).ponds():
			assert_float(float(pond["area"])).is_between(float(water["min_area"]), float(water["max_area"]))
			assert_float(float(pond["depth"])).is_greater_equal(float(water["min_depth"]))

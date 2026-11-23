extends GdUnitTestSuite
## Settlements on the land (#428): a compact square city on flat ground inside its zone,
## towns apart from it, and the players' camp outside them all.

const RECIPES := ["res://modules/world/data/maps/grassland.json", "res://modules/world/data/maps/mixed.json"]


func _build(path: String, seed_value: int) -> Settlements:
	var recipe: Dictionary = Data.load_json(path)
	var land := WorldLand.new(recipe, seed_value)
	return Settlements.new(LandZones.new(land, recipe["zones"]), recipe["settlements"])


func test_every_map_has_a_square_city_on_flat_ground() -> void:
	for path: String in RECIPES:
		var cfg: Dictionary = (Data.load_json(path) as Dictionary)["settlements"]
		for seed_value in 6:
			var s := _build(path, seed_value)
			var city := s.city()
			var where := "%s seed %d" % [path.get_file(), seed_value]
			assert_bool(city.is_empty()).override_failure_message(where + ": no city").is_false()
			var foot: Rect2 = city["footprint"]
			assert_float(foot.size.x).override_failure_message(where + ": city too small").is_greater_equal(float(cfg["city"]["size"]))
			assert_float(foot.size.x).is_equal_approx(foot.size.y, 0.01)
			# Every part of it lies in the zone it was chosen from.
			var zone_id := int(city["zone"])
			for i in 5:
				for j in 5:
					var p := foot.position + foot.size * (Vector2(i, j) + Vector2(0.5, 0.5)) / 5.0
					assert_int(int(s.zones.zone_at(p.x, p.y)["id"])).override_failure_message(where + ": city off its zone").is_equal(zone_id)


func test_towns_keep_their_distance_and_the_camp_stays_outside() -> void:
	for path: String in RECIPES:
		var cfg: Dictionary = (Data.load_json(path) as Dictionary)["settlements"]
		for seed_value in 6:
			var s := _build(path, seed_value)
			var where := "%s seed %d" % [path.get_file(), seed_value]
			var places: Array[Dictionary] = [s.city()]
			places.append_array(s.towns())
			assert_int(s.towns().size()).is_less_equal(int(cfg["town"]["max"]))
			for t: Dictionary in s.towns():
				assert_float((t["footprint"] as Rect2).size.x).is_greater_equal(float(cfg["town"]["size"]))
				for other: Dictionary in places:
					if other == t:
						continue
					var gap := (t["centre"] as Vector2).distance_to(other["centre"])
					assert_float(gap).override_failure_message(where + ": towns too close").is_greater_equal(float(cfg["town"]["spacing"]))
			var inner := s.zones.land.bounds().grow(-float(cfg["edge_margin"]) + 0.01)
			for place: Dictionary in places:
				assert_bool(inner.encloses(place["footprint"])).override_failure_message(where + ": settlement at the map's edge").is_true()
			var camp := s.camp()
			for place: Dictionary in places:
				var near := (place["footprint"] as Rect2).grow(float(cfg["camp"]["clearance"]))
				assert_bool(near.has_point(camp)).override_failure_message(where + ": camp in a settlement").is_false()


func test_each_settlement_has_a_level_and_a_way_in_on_every_side() -> void:
	var s := _build(RECIPES[0], 2)
	for place: Dictionary in [s.city()] + s.towns():
		var connectors: Array = place["connectors"]
		assert_int(connectors.size()).is_equal(4)
		var foot: Rect2 = place["footprint"]
		for c: Vector3 in connectors:
			# On the footprint's edge, at the settlement's level.
			var edge := minf(minf(absf(c.x - foot.position.x), absf(c.x - foot.end.x)), minf(absf(c.z - foot.position.y), absf(c.z - foot.end.y)))
			assert_float(edge).is_less(0.01)
			assert_float(c.y).is_equal_approx(float(place["level"]), 0.001)


func test_the_same_seed_gives_the_same_settlements() -> void:
	var a := _build(RECIPES[0], 9)
	var b := _build(RECIPES[0], 9)
	assert_dict(a.city()).is_equal(b.city())
	assert_vector(a.camp()).is_equal(b.camp())

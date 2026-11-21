extends GdUnitTestSuite
## Roads join the settlements (#428): the camp to the city, the city to each town, routed
## over the land round water and through no other settlement (nor the camp's pad).

const RECIPES := ["res://modules/world/data/maps/grassland.json", "res://modules/world/data/maps/mixed.json"]


func _build(path: String, seed_value: int) -> RoadNetwork:
	var recipe: Dictionary = Data.load_json(path)
	var zones := LandZones.new(WorldLand.new(recipe, seed_value), recipe["zones"])
	return RoadNetwork.new(Settlements.new(zones, recipe["settlements"]), recipe["roads"])


func test_the_camp_and_every_town_are_joined_to_the_city() -> void:
	for path: String in RECIPES:
		for seed_value in 4:
			var net := _build(path, seed_value)
			var places := net.settlements
			var where := "%s seed %d" % [path.get_file(), seed_value]
			assert_int(net.roads().size()).override_failure_message(where).is_equal(1 + places.towns().size())
			var camp_road: Dictionary = net.roads()[0]
			var points: PackedVector2Array = camp_road["points"]
			# It leaves from the middle of the camp pad's side nearest the city (#420).
			var leaves := false
			for c: Vector3 in places.camp_place()["connectors"]:
				leaves = leaves or points[0].distance_to(Vector2(c.x, c.z)) < 1.0
			assert_bool(leaves).override_failure_message(where + ": road misses the camp").is_true()
			var reaches := false
			for c: Vector3 in places.city()["connectors"]:
				reaches = reaches or points[points.size() - 1].distance_to(Vector2(c.x, c.z)) < 1.0
			assert_bool(reaches).override_failure_message(where + ": road misses the city").is_true()


func test_roads_keep_out_of_water_and_other_settlements() -> void:
	for path: String in RECIPES:
		for seed_value in 4:
			var net := _build(path, seed_value)
			var land := net.settlements.zones.land
			var where := "%s seed %d" % [path.get_file(), seed_value]
			var places := net.settlements.all_places()
			for road: Dictionary in net.roads():
				for p: Vector2 in road["points"]:
					assert_bool(is_nan(land.water_level(p.x, p.y))).override_failure_message(where + ": road in water at %s" % p).is_true()
					for place: Dictionary in places:
						var inside := (place["footprint"] as Rect2).grow(-2.0)
						assert_bool(inside.has_point(p)).override_failure_message(where + ": road through a settlement at %s" % p).is_false()


func test_roads_are_sampled_evenly_and_turn_smoothly() -> void:
	var net := _build(RECIPES[0], 3)
	var sample := float((Data.load_json(RECIPES[0]) as Dictionary)["roads"]["sample"])
	for road: Dictionary in net.roads():
		var points: PackedVector2Array = road["points"]
		for i in range(1, points.size() - 1):
			assert_float(points[i].distance_to(points[i - 1])).is_between(sample * 0.5, sample * 1.5)
			var a := (points[i] - points[i - 1]).normalized()
			var b := (points[i + 1] - points[i]).normalized()
			# No kinks: under 30 degrees between one 4 m step and the next.
			assert_float(a.dot(b)).is_greater(cos(deg_to_rad(30.0)))


func test_the_same_seed_gives_the_same_roads() -> void:
	var a := _build(RECIPES[0], 6)
	var b := _build(RECIPES[0], 6)
	assert_int(a.roads().size()).is_equal(b.roads().size())
	for i in a.roads().size():
		assert_array(Array(a.roads()[i]["points"])).is_equal(Array(b.roads()[i]["points"]))

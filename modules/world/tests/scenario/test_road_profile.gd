extends GdUnitTestSuite
## A road's height along its length (#428): following the land, never steeper than its
## kind allows, level with the settlements it joins, with tunnels where it would cut too deep
## and bridges where it would stand too high.

const RECIPES := ["res://modules/world/data/maps/grassland.json", "res://modules/world/data/maps/mixed.json"]


func _build(path: String, seed_value: int) -> RoadNetwork:
	var recipe: Dictionary = Data.load_json(path)
	var zones := LandZones.new(WorldLand.new(recipe, seed_value), recipe["zones"])
	return RoadNetwork.new(Settlements.new(zones, recipe["settlements"]), recipe["roads"])


func test_no_road_is_steeper_than_its_kind_allows() -> void:
	for path: String in RECIPES:
		for seed_value in 4:
			var net := _build(path, seed_value)
			for road: Dictionary in net.roads():
				var points: PackedVector2Array = road["points"]
				var heights: PackedFloat32Array = road["heights"]
				assert_int(heights.size()).is_equal(points.size())
				var limit := float(road["max_grade"]) * 1.02
				for i in range(1, points.size()):
					var grade := absf(heights[i] - heights[i - 1]) / points[i].distance_to(points[i - 1])
					assert_float(grade).override_failure_message("%s seed %d %s: %.3f at %s" % [path.get_file(), seed_value, road["from"], grade, points[i]]).is_less_equal(limit)


func test_a_road_meets_the_city_at_its_level() -> void:
	for seed_value in 4:
		var net := _build(RECIPES[0], seed_value)
		var city_level := float(net.settlements.city()["level"])
		for road: Dictionary in net.roads():
			var heights: PackedFloat32Array = road["heights"]
			assert_float(heights[heights.size() - 1]).is_equal_approx(city_level, 0.01)


func test_earthworks_are_marked_where_they_get_too_big() -> void:
	for path: String in RECIPES:
		for seed_value in 4:
			var net := _build(path, seed_value)
			var land := net.settlements.zones.land
			for road: Dictionary in net.roads():
				var points: PackedVector2Array = road["points"]
				var heights: PackedFloat32Array = road["heights"]
				var tunnel := _marked(road["tunnels"], points.size())
				var bridge := _marked(road["bridges"], points.size())
				for i in points.size():
					var ground := land.height(points[i].x, points[i].y)
					var cut := ground - heights[i]
					var fill := heights[i] - ground
					if cut > float(road["max_cut"]):
						assert_bool(tunnel[i]).override_failure_message("deep cut not a tunnel at %s" % points[i]).is_true()
					if fill > float(road["max_fill"]):
						assert_bool(bridge[i]).override_failure_message("high fill not a bridge at %s" % points[i]).is_true()


## Per sample, whether it lies in one of `spans` ([first, last] sample indices).
func _marked(spans: Array, count: int) -> Array[bool]:
	var out: Array[bool] = []
	out.resize(count)
	out.fill(false)
	for span: Vector2i in spans:
		for i in range(span.x, span.y + 1):
			out[i] = true
	return out


func test_roads_mostly_follow_the_land() -> void:
	var net := _build(RECIPES[0], 3)
	var land := net.settlements.zones.land
	for road: Dictionary in net.roads():
		var points: PackedVector2Array = road["points"]
		var heights: PackedFloat32Array = road["heights"]
		var off := 0.0
		for i in points.size():
			off += absf(land.height(points[i].x, points[i].y) - heights[i])
		# On gentle grassland the road sits within a couple of metres of the land on average.
		assert_float(off / points.size()).is_less(2.0)

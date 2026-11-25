extends GdUnitTestSuite
## The home island (#454): every seed is one main island in the sea holding the city, the
## towns and the camp; beaches on gentle shores, rock on steep ones; the camp near the water
## with a harbour spot on the shore beside it; nothing placed out at sea.

const RECIPES := ["res://modules/world/data/maps/grassland.json", "res://modules/world/data/maps/mixed.json"]
const SEEDS := 6


func _places(path: String, seed_value: int) -> Settlements:
	var recipe: Dictionary = Data.load_json(path)
	var land := WorldLand.new(recipe, seed_value)
	return Settlements.new(LandZones.new(land, recipe["zones"]), recipe["settlements"])


## Whether every one of a 5 x 5 spread of points over `foot` is main-island land.
func _on_main_island(zones: LandZones, foot: Rect2) -> bool:
	for i in 5:
		for j in 5:
			var p := foot.position + foot.size * (Vector2(i, j) + Vector2(0.5, 0.5)) / 5.0
			if zones.land.is_sea(p.x, p.y) or str(zones.zone_at(p.x, p.y).get("kind", "")) == "islet":
				return false
	return true


func test_every_seed_is_one_main_island_holding_the_city_the_towns_and_the_camp() -> void:
	for path: String in RECIPES:
		for seed_value in SEEDS:
			var s := _places(path, seed_value)
			var where := "%s seed %d" % [path.get_file(), seed_value]
			assert_bool(s.city().is_empty()).override_failure_message(where + ": no city").is_false()
			# The hillier recipe can leave no flat ground for a town (it could before the coast).
			if path == RECIPES[0]:
				assert_int(s.towns().size()).override_failure_message(where + ": no town").is_greater(0)
			for place: Dictionary in [s.city()] + s.towns() + [s.camp_place()]:
				assert_bool(_on_main_island(s.zones, place["footprint"])).override_failure_message("%s: %s off the main island" % [where, place["kind"]]).is_true()


func test_the_edge_of_the_map_is_open_sea_at_sea_level() -> void:
	for path: String in RECIPES:
		var recipe: Dictionary = Data.load_json(path)
		var coast: Dictionary = recipe["coast"]
		for seed_value in SEEDS:
			var land := WorldLand.new(recipe, seed_value)
			var b := land.bounds()
			var where := "%s seed %d" % [path.get_file(), seed_value]
			for k in 40:
				var t := float(k) / 40.0
				for p: Vector2 in [b.position + Vector2(b.size.x * t, 1.0), b.end - Vector2(b.size.x * t, 1.0),
						Vector2(b.position.x + 1.0, b.position.y + b.size.y * t), Vector2(b.end.x - 1.0, b.position.y + b.size.y * t)]:
					assert_bool(land.is_sea(p.x, p.y)).override_failure_message("%s: land at the map's edge %s" % [where, p]).is_true()
					assert_float(land.water_level(p.x, p.y)).is_equal(float(coast["sea_level"]))
					# Deep enough out there to tire a swimmer: the sea is the world's edge.
					assert_float(land.sea_level - land.height(p.x, p.y)).override_failure_message(where + ": shallow at the edge").is_greater(6.0)


func test_the_island_keeps_about_the_land_it_had_with_a_few_islets() -> void:
	var islets := 0
	for seed_value in SEEDS:
		var s := _places(RECIPES[0], seed_value)
		var land := s.zones.land
		var dry := 0
		var step := 16.0
		var b := land.bounds()
		var x := b.position.x + step / 2.0
		while x < b.end.x:
			var z := b.position.y + step / 2.0
			while z < b.end.y:
				if not land.is_sea(x, z):
					dry += 1
				z += step
			x += step
		var area := dry * step * step / 1.0e6
		# The 2 km square the map was before the island: about 4.2 square kilometres.
		assert_float(area).override_failure_message("seed %d: %.2f km2 of land" % [seed_value, area]).is_between(3.6, 4.6)
		islets += s.zones.zones(&"islet").size()
	assert_int(islets).override_failure_message("no islets on any seed").is_greater(SEEDS)


func test_beaches_are_sand_on_gentle_shores_and_steep_shores_are_rock() -> void:
	var recipe: Dictionary = Data.load_json(RECIPES[1])
	var rock_to := float(recipe["biomes"]["rock_grade_to"])
	var wash := float(recipe["coast"]["beach"]["wash"])
	var sandy := 0
	var rocky := 0
	for seed_value in 3:
		var land := WorldLand.new(recipe, seed_value)
		var b := land.bounds()
		# Along rays out from the middle, the last land before the sea is the shore.
		for a in 360:
			var dir := Vector2.from_angle(TAU * a / 360.0)
			var shore := Vector2.INF
			var r := b.size.x / 2.0
			while r > 0.0:
				var p := dir * r
				if not land.is_sea(p.x, p.y):
					shore = p
					break
				r -= 1.0
			if shore == Vector2.INF:
				continue
			var grade := land.grade(shore.x, shore.y)
			var sand := land.sand(shore.x, shore.y, grade)
			var rock := land.rock(shore.x, shore.y, grade)
			if grade > rock_to:
				assert_float(sand).override_failure_message("seed %d: sand on a steep shore at %s" % [seed_value, shore]).is_equal(0.0)
			# Sand or rock down to the water, never grass, however steep the shore (a cliff top the
			# ray steps onto straight from the sea is no waterline).
			if land.land_height(shore.x, shore.y) - land.sea_level < wash:
				assert_float(sand + rock).override_failure_message("seed %d: grass on the shore at %s (grade %.2f)" % [seed_value, shore, grade]).is_greater_equal(0.95)
			if sand > 0.5:
				sandy += 1
			if rock > 0.5:
				rocky += 1
	assert_int(sandy).override_failure_message("no beaches").is_greater(50)
	assert_int(rocky).override_failure_message("no rocky shores").is_greater(5)


func test_the_camp_is_close_to_the_water_with_a_harbour_on_the_shore_beside_it() -> void:
	for path: String in RECIPES:
		var recipe: Dictionary = Data.load_json(path)
		var cfg: Dictionary = recipe["settlements"]
		var near: Array = cfg["camp"]["sea"]
		var harbour_cfg: Dictionary = cfg["harbour"]
		for seed_value in SEEDS:
			var s := _places(path, seed_value)
			var land := s.zones.land
			var where := "%s seed %d" % [path.get_file(), seed_value]
			var camp := s.camp()
			var to_sea := s.zones.sea_distance(camp.x, camp.y)
			assert_float(to_sea).override_failure_message("%s: camp %.0f m from the sea" % [where, to_sea]).is_between(float(near[0]), float(near[1]))
			var h := s.harbour()
			assert_bool(h.is_empty()).override_failure_message(where + ": no harbour").is_false()
			if h.is_empty():
				continue
			var root: Vector3 = h["root"]
			var facing: Vector2 = h["facing"]
			var length := float(h["length"])
			var at := Vector2(root.x, root.z)
			assert_float(at.distance_to(camp)).override_failure_message(where + ": harbour out of reach").is_less_equal(float(harbour_cfg["reach"]))
			assert_float(root.y).is_equal(land.sea_level)
			# On the shoreline: land just behind it, sea just in front.
			var behind := at - facing * 2.0
			var ahead := at + facing * 2.0
			assert_bool(land.is_sea(behind.x, behind.y)).override_failure_message(where + ": harbour root out at sea").is_false()
			assert_bool(land.is_sea(ahead.x, ahead.y)).override_failure_message(where + ": harbour faces land").is_true()
			assert_float(facing.length()).is_equal_approx(1.0, 0.001)
			assert_float(length).is_between(float(harbour_cfg["length"][0]), float(harbour_cfg["length"][1]))
			# Open water all along the jetty and deep enough at its end.
			var d := 2.0
			while d <= length:
				var p := at + facing * d
				assert_bool(land.is_sea(p.x, p.y)).override_failure_message("%s: land under the jetty %.0f m out" % [where, d]).is_true()
				d += 2.0
			var end := at + facing * length
			var depth := land.sea_level - land.height(end.x, end.y)
			assert_float(depth).override_failure_message(where + ": shallow at the jetty's end").is_greater_equal(float(harbour_cfg["min_depth"]))
			assert_float(float(h["depth"])).is_equal_approx(depth, 0.01)
			assert_bool((h["footprint"] as Rect2).intersects(s.camp_place()["footprint"])).override_failure_message(where + ": harbour on the camp pad").is_false()


func test_nothing_is_placed_in_the_sea_or_on_the_harbour() -> void:
	var recipe: Dictionary = Data.load_json(RECIPES[0])
	for seed_value in 3:
		var built := MapRender.build(recipe, seed_value)
		var land: WorldLand = built["land"]
		var places: Settlements = built["places"]
		var harbour: Rect2 = places.harbour()["footprint"]
		var where := "seed %d" % seed_value
		var net: RoadNetwork = built["net"]
		for road: Dictionary in net.roads():
			for p: Vector2 in road["points"]:
				assert_bool(land.is_sea(p.x, p.y)).override_failure_message("%s: %s %s in the sea at %s" % [where, road["kind"], road["from"], p]).is_false()
				assert_bool(harbour.has_point(p)).override_failure_message("%s: %s %s over the harbour" % [where, road["kind"], road["from"]]).is_false()
		var sites: MapSites = built["sites"]
		for site: Dictionary in sites.sites():
			var foot: Rect2 = site["footprint"]
			assert_bool(foot.intersects(harbour)).override_failure_message("%s: %s on the harbour" % [where, site["kind"]]).is_false()
			for c: Vector2 in [foot.position, foot.end, foot.get_center(), Vector2(foot.position.x, foot.end.y), Vector2(foot.end.x, foot.position.y)]:
				assert_bool(land.is_sea(c.x, c.y)).override_failure_message("%s: %s in the sea" % [where, site["kind"]]).is_false()
		var power: MapPower = built["power"]
		for line: Dictionary in power.lines():
			for p: Vector2 in line["points"]:
				assert_bool(land.is_sea(p.x, p.y)).override_failure_message("%s: power in the sea" % where).is_false()
				assert_bool(harbour.has_point(p)).override_failure_message("%s: power on the harbour" % where).is_false()


func test_the_sea_is_a_water_body_and_a_swimmer_out_past_its_limit_knows_it() -> void:
	var recipe: Dictionary = Data.load_json(RECIPES[0])
	var built := MapRender.build(recipe, 1)
	built["recipe"] = recipe
	var shape := MapShape.new(built, recipe["water"])
	var water := shape.water as MapWater
	assert_int(water.sea).is_greater_equal(0)
	var b := shape.extent()
	var out := Vector2(b.position.x + 20.0, b.get_center().y)
	assert_int(water.body_at(out.x, out.y)).is_equal(water.sea)
	assert_float(water.level_at(out.x, out.y)).is_equal(shape.sea_level())
	# On the island there is no sea, and every pond is still its own body.
	var camp := shape.camp()
	assert_int(water.body_at(camp.x, camp.z)).is_equal(-1)
	for i in shape.land.ponds().size():
		var c: Vector2 = shape.land.ponds()[i]["centre"]
		assert_int(water.body_at(c.x, c.y)).is_equal(i)
	# The sea's surface covers the sea but not the island's middle.
	var mesh := WaterView.sea_mesh(water, shape.sea_level())
	assert_object(mesh).is_not_null()
	var covers := func(p: Vector2) -> bool:
		for r in shape.land.sea_runs():
			if r.has_point(p):
				return true
		return false
	assert_bool(covers.call(out)).is_true()
	assert_bool(covers.call(Vector2(camp.x, camp.z))).is_false()
	# The harbour is exposed with the jetty's way out and the water there.
	var h := shape.harbour()
	assert_bool(h.is_empty()).is_false()
	assert_float((h["facing"] as Vector3).y).is_equal(0.0)
	assert_float(float(h["depth"])).is_greater_equal(float(recipe["settlements"]["harbour"]["min_depth"]))

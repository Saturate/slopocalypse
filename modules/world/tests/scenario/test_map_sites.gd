extends GdUnitTestSuite
## Sites and props on a generated map (#429) and the remoteness they read (#419), held to
## whole-map rules (#415) over both shipped recipes and a few seeds.

const SEEDS := [1, 2, 3]

static var _worlds: Array[Dictionary] = []


func before() -> void:
	for map in ["grassland", "mixed"]:
		var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://modules/world/data/maps/%s.json" % map))
		for seed_value: int in SEEDS:
			var world := MapRender.build(recipe, seed_value)
			world["recipe"] = recipe
			world["name"] = "%s seed %d" % [map, seed_value]
			_worlds.append(world)


func after() -> void:
	_worlds.clear()


func test_every_map_gets_sites() -> void:
	for world in _worlds:
		assert_int((world["sites"] as MapSites).sites().size()).override_failure_message(world["name"]).is_greater(3)


func test_no_site_overlaps_another_a_road_a_settlement_or_water() -> void:
	for world in _worlds:
		var placed: Array[Dictionary] = (world["sites"] as MapSites).sites()
		var places: Settlements = world["places"]
		var net: RoadNetwork = world["net"]
		var zones: LandZones = world["zones"]
		for a in placed.size():
			var foot: Rect2 = placed[a]["footprint"]
			var what := "%s: %s at %s" % [world["name"], placed[a]["kind"], placed[a]["centre"]]
			for b in range(a + 1, placed.size()):
				assert_bool(foot.intersects(placed[b]["footprint"])).override_failure_message(what + " overlaps a " + str(placed[b]["kind"])).is_false()
			var all: Array[Dictionary] = places.towns().duplicate()
			all.append(places.city())
			for place in all:
				assert_bool(foot.intersects(place["footprint"])).override_failure_message(what + " is in a settlement").is_false()
			for road: Dictionary in net.roads():
				var half := float(road["width"]) / 2.0
				for p: Vector2 in road["points"]:
					assert_bool(foot.grow(half).has_point(p)).override_failure_message(what + " is on a road").is_false()
			for corner: Vector2 in [foot.position, foot.end, Vector2(foot.position.x, foot.end.y), Vector2(foot.end.x, foot.position.y), foot.get_center()]:
				assert_str(str(zones.zone_at(corner.x, corner.y).get("kind", ""))).override_failure_message(what + " is in water").is_not_equal("water")


func test_every_site_keeps_its_kinds_rules() -> void:
	for world in _worlds:
		var kinds: Dictionary = world["recipe"]["sites"]["kinds"]
		var far: MapRemoteness = world["remoteness"]
		var zones: LandZones = world["zones"]
		var seen: Dictionary[String, int] = {}
		for site: Dictionary in (world["sites"] as MapSites).sites():
			var rule: Dictionary = kinds[site["kind"]]
			var c: Vector2 = site["centre"]
			var what := "%s: %s at %s" % [world["name"], site["kind"], c]
			assert_bool((rule["zones"] as Array).has(str(zones.zone_at(c.x, c.y)["kind"]))).override_failure_message(what + " on the wrong zone").is_true()
			var r := far.at(c.x, c.y)
			assert_float(r).override_failure_message(what + " too near or far").is_between(float(rule["remoteness"][0]), float(rule["remoteness"][1]))
			seen[site["kind"]] = seen.get(site["kind"], 0) + 1
		for kind: String in seen:
			assert_int(seen[kind]).override_failure_message("%s: too many %s" % [world["name"], kind]).is_less_equal(int(kinds[kind]["count"][1]))


func test_the_lone_cabin_is_far_out_and_farms_are_not() -> void:
	for world in _worlds:
		for site: Dictionary in (world["sites"] as MapSites).sites():
			if site["kind"] == "cabin":
				assert_float(float(site["remoteness"])).is_greater_equal(0.7)
			if site["kind"] == "farm":
				assert_float(float(site["remoteness"])).is_less_equal(0.65)


func test_remoteness_is_zero_with_people_and_rises_away_from_them() -> void:
	for world in _worlds:
		var far: MapRemoteness = world["remoteness"]
		var places: Settlements = world["places"]
		var city: Vector2 = places.city()["centre"]
		assert_float(far.at(city.x, city.y)).is_equal(0.0)
		var camp := places.camp()
		assert_float(far.at(camp.x, camp.y)).is_equal(0.0)
		var b := (world["land"] as WorldLand).bounds()
		var furthest := 0.0
		for corner: Vector2 in [b.position + Vector2(20, 20), b.end - Vector2(20, 20), Vector2(b.position.x + 20, b.end.y - 20), Vector2(b.end.x - 20, b.position.y + 20)]:
			furthest = maxf(furthest, far.at(corner.x, corner.y))
		assert_float(furthest).override_failure_message(world["name"]).is_greater(0.5)

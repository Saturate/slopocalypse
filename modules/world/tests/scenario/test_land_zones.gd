extends GdUnitTestSuite
## Zones on the land (#427): every part of the map has a kind, connected ground of one kind
## is one zone, every map has flat ground big enough for a city, and the player starts on
## flat dry ground near an edge.

const GRASSLAND := "res://modules/world/data/maps/grassland.json"


func _recipe() -> Dictionary:
	return Data.load_json(GRASSLAND)


func _zones(seed_value: int) -> LandZones:
	var recipe := _recipe()
	return LandZones.new(WorldLand.new(recipe, seed_value), recipe["zones"])


func test_every_map_has_flat_ground_for_a_city() -> void:
	var recipe := _recipe()
	var city: Dictionary = recipe["zones"]["uses"]["city"]
	for seed_value in 20:
		var best := _zones(seed_value).best(&"city")
		assert_bool(best.is_empty()).override_failure_message("seed %d: nowhere for a city" % seed_value).is_false()
		assert_float(float(best["area"])).is_greater_equal(float(city["min_area"]))
		assert_bool((city["kinds"] as Array).has(best["kind"])).is_true()


func test_every_cell_belongs_to_a_zone_of_a_known_kind() -> void:
	var zones := _zones(4)
	var land := zones.land
	var b := land.bounds()
	for i in 24:
		for j in 24:
			var p := b.position + b.size * (Vector2(i, j) + Vector2(0.5, 0.5)) / 24.0
			var zone := zones.zone_at(p.x, p.y)
			assert_bool(zone.is_empty()).is_false()
			assert_bool(LandZones.KINDS.has(str(zone["kind"]))).is_true()


func test_zones_follow_the_land() -> void:
	var zones := _zones(7)
	var land := zones.land
	for pond: Dictionary in land.ponds():
		var c: Vector2 = pond["centre"]
		# Its deepest survey point sits on a corner of the zone cells: one of the four round it
		# is water (a small pond may miss the middles of the others).
		var cell := zones.cell_size()
		var wet := false
		for d: Vector2 in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
			var p := c + d * cell
			wet = wet or str(zones.zone_at(p.x, p.y)["kind"]) == "water"
		assert_bool(wet).override_failure_message("pond at %s not in a water zone" % c).is_true()
	for zone: Dictionary in zones.zones(&"flat"):
		var c: Vector2 = zone["centre"]
		if zones.zone_at(c.x, c.y).get("id") == zone["id"]:
			assert_float(land.grade(c.x, c.y)).is_less(float(_recipe()["zones"]["slope_grade"]))


func test_the_player_starts_on_flat_dry_ground_near_the_sea() -> void:
	var recipe := _recipe()
	var cfg: Dictionary = recipe["zones"]
	# Eight seeds: building zones takes a while, and the city test already covers twenty.
	for seed_value in 8:
		var zones := _zones(seed_value)
		var spawn := zones.spawn()
		var land := zones.land
		assert_bool(is_nan(land.water_level(spawn.x, spawn.y))).is_true()
		assert_float(land.grade(spawn.x, spawn.y)).override_failure_message("seed %d: spawn on a slope" % seed_value).is_less(float(recipe["walkable"]["flat_grade"]) * 1.5)
		# On an island the edge is the sea (#454), measured on the zone grid.
		var to_edge := zones.sea_distance(spawn.x, spawn.y)
		assert_float(to_edge).is_between(float(cfg["spawn_margin"]) - 1.0, float(cfg["spawn_edge"]))


func test_the_same_seed_gives_the_same_zones() -> void:
	var a := _zones(9)
	var b := _zones(9)
	assert_int(a.zones(&"").size()).is_equal(b.zones(&"").size())
	assert_vector(a.spawn()).is_equal(b.spawn())
	assert_dict(a.best(&"city")).is_equal(b.best(&"city"))

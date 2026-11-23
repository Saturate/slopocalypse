extends GdUnitTestSuite
## The players' camp on generated maps (#420): its pad is level, the respawn, the board, the
## trader, the transport and the car stand inside the fence on the pad (where the world, the
## missions and the trader modules put them), the highway leaves through the gate, and no
## road, site, power line or tree crowds it.

const SEEDS := [1, 4]
const MISSIONS := "res://modules/missions/missions_module.gd"
const TRADER := "res://modules/trader/trader_module.gd"
## Metres apart the fence is sampled at.
const STEP := 0.5

## Each {name, shape (MapShape), camp (CampLayout)}.
static var _maps: Array[Dictionary] = []


func before() -> void:
	var cfg: Dictionary = (Data.load_json(CampLayout.CONFIG) as Dictionary)["camp"]
	for map in ["grassland", "mixed"]:
		var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://modules/world/data/maps/%s.json" % map))
		for seed_value: int in SEEDS:
			var built := MapRender.build(recipe, seed_value)
			built["recipe"] = recipe
			var shape := MapShape.new(built, recipe.get("water", {}))
			var pad := shape.camp_pad()
			_maps.append({"name": "%s seed %d" % [map, seed_value], "shape": shape, "camp": CampLayout.make(pad["centre"], pad["out"], pad["footprint"], cfg)})


func after() -> void:
	_maps.clear()


func test_the_pad_is_level_and_holds_the_fence() -> void:
	for m in _maps:
		var shape: MapShape = m["shape"]
		var camp: CampLayout = m["camp"]
		var pad := camp.pad
		for i in 9:
			for j in 9:
				var p := pad.position + pad.size * Vector2(i, j) / 8.0
				assert_float(shape.height_at(p.x, p.y)).override_failure_message("%s: pad not level at %s" % [m["name"], p]).is_equal_approx(camp.centre.y, 0.01)
		for run in camp.fence_runs():
			for end in run:
				assert_bool(pad.grow(-0.5).has_point(Vector2(end.x, end.z))).override_failure_message(str(m["name"]) + ": fence off the pad").is_true()


func test_everything_in_the_camp_stands_inside_the_fence_on_the_pad() -> void:
	for m in _maps:
		var shape: MapShape = m["shape"]
		var camp: CampLayout = m["camp"]
		for name in CampLayout.SPOTS:
			var at := camp.spot(name).origin
			var what := "%s: %s" % [m["name"], name]
			assert_bool(camp.inside(at, 1.0)).override_failure_message(what + " outside the fence").is_true()
			assert_float(shape.height_at(at.x, at.z)).override_failure_message(what + " off the pad").is_equal_approx(camp.centre.y, 0.01)


func test_the_highway_leaves_through_the_gate() -> void:
	for m in _maps:
		var shape: MapShape = m["shape"]
		var camp: CampLayout = m["camp"]
		var points := shape.highway()
		assert_int(points.size()).override_failure_message(str(m["name"]) + ": no highway").is_greater(2)
		var start := Vector3(points[0].x, camp.centre.y, points[0].y)
		var l := camp.local_of(start)
		# It starts in line with the gate, on the pad's edge just past it.
		assert_float(absf(l.x)).override_failure_message(str(m["name"]) + ": highway beside the gate").is_less(0.5)
		assert_float(l.y).is_greater(camp.half)
		assert_float(l.y - camp.half).is_less_equal(camp.pad.size.x / 2.0 - camp.half + 0.5)
		# And runs away from it: every point outside the fence.
		for p in points:
			assert_bool(camp.inside(Vector3(p.x, 0.0, p.y), -0.01)).override_failure_message(str(m["name"]) + ": highway inside the camp").is_false()
		# Its first stretch heads straight out, square to the gate.
		var lead := camp.local_of(Vector3(points[3].x, 0.0, points[3].y))
		assert_float(absf(lead.x)).is_less(0.5)
		assert_float(lead.y).is_greater(l.y)


func test_no_road_crosses_the_camp_but_at_the_gate() -> void:
	for m in _maps:
		var shape: MapShape = m["shape"]
		var camp: CampLayout = m["camp"]
		for run in camp.fence_runs():
			var steps := ceili(run[0].distance_to(run[1]) / STEP)
			for k in steps + 1:
				var p := run[0].lerp(run[1], float(k) / steps)
				assert_float(shape.road_edge_distance(p.x, p.z)).override_failure_message("%s: road on the fence at %s" % [m["name"], p]).is_greater(0.0)
		# Inside the fence there is no road at all; the highway only meets the pad past the gate.
		for i in 17:
			for j in 17:
				var p := camp.point(Vector2(-camp.half, -camp.half) + Vector2(i, j) * camp.half * 2.0 / 16.0)
				if camp.in_gate(p, 0.6):
					continue
				assert_float(shape.road_edge_distance(p.x, p.z)).override_failure_message("%s: road inside the camp at %s" % [m["name"], p]).is_greater(0.0)


func test_sites_power_and_trees_keep_off_the_camp() -> void:
	var scatter: Dictionary = (Data.load_json(CampLayout.CONFIG) as Dictionary)["scatter"]
	for m in _maps:
		var shape: MapShape = m["shape"]
		var camp: CampLayout = m["camp"]
		for site in shape.site_list():
			assert_bool((site["footprint"] as Rect2).intersects(camp.pad)).override_failure_message(str(m["name"]) + ": a site on the camp").is_false()
		var reach := camp.pad.size.x / 2.0 * sqrt(2.0)
		assert_bool(shape.power_within(camp.centre.x, camp.centre.z, reach)).override_failure_message(str(m["name"]) + ": a power line through the camp").is_false()
		var power: Dictionary = scatter["power_clearance"]
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p := camp.point(corner * camp.half)
			assert_bool(shape.near_power(p.x, p.z, float(power["high_voltage"]), float(power["low_voltage"]))).is_false()
			# The scenery asks this before planting a tree or a rock.
			assert_bool(shape.near_camp(p.x, p.z, float(scatter["camp_clearance"]))).is_true()


func test_the_world_puts_the_spawn_and_the_car_in_the_camp() -> void:
	var m: Dictionary = _maps[0]
	var root := auto_free(WorldRoot.new()) as WorldRoot
	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	root.add_child(spawn)
	var car := Marker3D.new()
	car.name = "CarSpawn"
	root.add_child(car)
	root.place_on_map(m["shape"], (Data.load_json(CampLayout.CONFIG) as Dictionary)["camp"])
	var camp := root.camp
	assert_bool(camp.inside(spawn.position, 1.0)).is_true()
	assert_float(spawn.position.y).is_equal_approx(camp.centre.y + 1.0, 0.01)
	assert_bool(camp.inside(car.position, 1.0)).is_true()
	# Nose (+z) to the gate.
	assert_float(car.transform.basis.z.dot(camp.out)).is_greater(0.99)


func test_the_board_the_transport_and_the_trader_stand_on_their_spots() -> void:
	var camp: CampLayout = _maps[0]["camp"]
	var missions: Node = auto_free((load(MISSIONS) as GDScript).new())
	add_child(missions)
	var trader: Node = auto_free((load(TRADER) as GDScript).new())
	add_child(trader)
	EventBus.publish(&"world.ready", {"spawn": camp.spot("respawn").origin + Vector3.UP, "camp": camp})
	for entry: Array in [[missions.get_node("MissionBoard"), "board"], [missions.get_node("Transport"), "transport"], [trader.get_node("TraderStall"), "trader"]]:
		var node := entry[0] as Node3D
		assert_bool(node.global_transform.is_equal_approx(camp.spot(entry[1]))).override_failure_message(str(entry[1]) + " off its spot").is_true()
		assert_bool(camp.inside(node.global_position, 1.0)).is_true()

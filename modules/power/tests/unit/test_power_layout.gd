extends GdUnitTestSuite
## PowerLayout: towers turned to bisect their line, standing on the lowest ground under their
## feet, wires hung between matching attach points without crossing (along a line, at a tap
## and out of the substation's terminals), every span hanging as many wires as both its
## towers carry, and the towers' wires high enough for the recipes' clearance rules.

const RECIPES := ["grassland", "mixed"]


func _config() -> Dictionary:
	return Data.load_json(PowerLayout.CONFIG)


func _flat(_x: float, _z: float) -> float:
	return 10.0


func _line(kind: String, from: String, points: Array[Vector3]) -> Dictionary:
	return {"kind": kind, "from": from, "to": "town 0", "points": points, "sag": 0.02}


## Where a tower's front (-z) points, on the ground plane.
func _front(t: Dictionary) -> Vector2:
	var f := -(t["transform"] as Transform3D).basis.z
	return Vector2(f.x, f.z).normalized()


func _plan(lines: Array, station := {}) -> Dictionary:
	return PowerLayout.plan(lines, station, _config(), _flat)


## Every pair of wires in `spans` that cross in plan view without sharing an end, with less
## than `margin` metres between them where they cross.
static func touching(spans: Array, margin: float) -> Array[String]:
	var out: Array[String] = []
	for i in spans.size():
		var a: Dictionary = spans[i]
		for j in range(i + 1, spans.size()):
			var b: Dictionary = spans[j]
			var ends := [a["from"], a["to"]]
			if ends.has(b["from"]) or ends.has(b["to"]):
				continue
			var p0: Vector3 = a["from"]
			var p1: Vector3 = a["to"]
			var q0: Vector3 = b["from"]
			var q1: Vector3 = b["to"]
			var hit: Variant = Geometry2D.segment_intersects_segment(Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), Vector2(q0.x, q0.z), Vector2(q1.x, q1.z))
			if hit == null:
				continue
			var at: Vector2 = hit
			var ta := at.distance_to(Vector2(p0.x, p0.z)) / maxf(Vector2(p0.x, p0.z).distance_to(Vector2(p1.x, p1.z)), 0.001)
			var tb := at.distance_to(Vector2(q0.x, q0.z)) / maxf(Vector2(q0.x, q0.z).distance_to(Vector2(q1.x, q1.z)), 0.001)
			var ya := WireCurve.point_at(p0, p1, WireCurve.sag_for(p0, p1, float(a["sag"])), ta).y
			var yb := WireCurve.point_at(q0, q1, WireCurve.sag_for(q0, q1, float(b["sag"])), tb).y
			if absf(ya - yb) < margin:
				out.append("wires %d and %d cross at %s, %.2f m apart" % [i, j, at, absf(ya - yb)])
	return out


static func all_spans(plan: Dictionary) -> Array:
	var out: Array = []
	for wire_set: Dictionary in plan["wires"]:
		out.append_array(wire_set["spans"])
	return out


func test_the_config_is_sound() -> void:
	assert_array(PowerLayout.check(_config())).is_empty()


func test_a_corner_tower_bisects_its_line_and_the_ends_face_along_it() -> void:
	var points: Array[Vector3] = [Vector3(0, 10, 0), Vector3(200, 10, 0), Vector3(200, 10, 200)]
	var towers: Array = _plan([_line("high_voltage", "town 1", points)])["towers"]
	assert_int(towers.size()).is_equal(3)
	assert_vector(_front(towers[0])).is_equal_approx(Vector2(1, 0), Vector2(0.001, 0.001))
	assert_vector(_front(towers[1])).is_equal_approx(Vector2(1, 1).normalized(), Vector2(0.001, 0.001))
	assert_vector(_front(towers[2])).is_equal_approx(Vector2(0, 1), Vector2(0.001, 0.001))


func test_a_tower_stands_on_the_lowest_ground_under_its_turned_feet() -> void:
	var cfg := _config()
	var slope := func(x: float, _z: float) -> float: return x * 0.1
	# Diagonal, so the feet are turned 45 degrees: the lowest is base/2 * sqrt(2) down-slope.
	var points: Array[Vector3] = [Vector3(0, 0, 0), Vector3(150, 0, -150)]
	var towers: Array = PowerLayout.plan([_line("high_voltage", "town 1", points)], {}, cfg, slope)["towers"]
	var base := float(VoxLatticePylon.new().with_defaults(towers[0]["params"])["base"])
	var y := (towers[0]["transform"] as Transform3D).origin.y
	assert_float(y).is_equal_approx(-base / 2.0 * sqrt(2.0) * 0.1 - float(cfg["sink"]), 0.01)


func test_wires_join_matching_attach_points_without_crossing() -> void:
	for kind: String in ["high_voltage", "low_voltage"]:
		var points: Array[Vector3] = [Vector3(0, 10, 0), Vector3(0, 10, -40), Vector3(30, 10, -80)]
		var plan := _plan([_line(kind, "town 0", points)])
		var towers: Array = plan["towers"]
		var spans: Array = (plan["wires"][0] as Dictionary)["spans"]
		var conductors: int = (towers[0]["attach"] as Array).size()
		assert_int(conductors).is_greater_equal(2)
		assert_int(spans.size()).is_equal(conductors * 2)
		for s: Dictionary in spans:
			assert_str(str(s["kind"])).is_equal(kind)
		assert_array(touching(spans, 0.5)).is_empty()


func test_a_tap_takes_its_own_lower_arm_facing_the_tap_line() -> void:
	var trunk: Array[Vector3] = [Vector3(0, 10, 0), Vector3(40, 10, 0), Vector3(80, 10, 0)]
	for angle: float in [35.0, 60.0, 90.0, 120.0, 145.0]:
		var away := Vector3(cos(deg_to_rad(angle)), 0, sin(deg_to_rad(angle))) * 40.0
		var tap: Array[Vector3] = [Vector3(40, 10, 0), Vector3(40, 10, 0) + away, Vector3(40, 10, 0) + away * 2.0]
		var plan := _plan([_line("low_voltage", "town 0", trunk), _line("low_voltage", "line 0", tap)])
		var towers: Array = plan["towers"]
		assert_int(towers.size()).is_equal(5)
		var junction: Dictionary = towers[1]
		assert_float(float(junction["params"]["tap"])).is_greater_equal(0.0)
		assert_int((junction["tap"] as Array).size()).is_equal((junction["attach"] as Array).size())
		# The tap's wires leave from its own arm, below the line's.
		var spans: Array = (plan["wires"][1] as Dictionary)["spans"]
		for s: Dictionary in spans.slice(0, (junction["tap"] as Array).size()):
			assert_bool((junction["tap"] as Array).has(s["from"])).is_true()
		assert_array(touching(all_spans(plan), 0.5)).override_failure_message("tap at %d degrees" % angle).is_empty()


func test_lines_from_the_substation_start_on_terminals_facing_them_without_crossing() -> void:
	var station := {"centre": Vector3(0, 10, 0), "size": 32.0, "base": 9.0}
	var lines := []
	for i in 4:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 4.0)
		var terminal := Vector3(0, 10, 0) + dir * 10.0
		var pts: Array[Vector3] = [terminal, terminal + dir * 200.0, terminal + dir * 450.0]
		lines.append(_line("high_voltage", "substation", pts))
	var plan := _plan(lines, station)
	var towers: Array = plan["towers"]
	assert_str(towers[0]["generator"]).is_equal("VoxSubstation")
	var terminals := towers.filter(func(t: Dictionary) -> bool: return t["generator"] == "VoxTerminalGantry")
	assert_int(terminals.size()).is_equal(4)
	for t: Dictionary in terminals:
		assert_float((t["transform"] as Transform3D).origin.y).is_equal(10.0)
	assert_array(touching(all_spans(plan), 1.0)).is_empty()
	# Every span hangs as many wires as both its towers carry.
	for wire_set: Dictionary in plan["wires"]:
		for p: Array in wire_set["pairs"]:
			assert_int(int(p[2])).is_equal((towers[int(p[0])]["attach"] as Array).size())
			assert_int(int(p[2])).is_equal((towers[int(p[1])]["attach"] as Array).size())


func test_the_towers_wires_are_as_high_as_the_recipes_count_on() -> void:
	var cfg := _config()
	var sink := float(cfg["sink"])
	for map: String in RECIPES:
		var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://modules/world/data/maps/%s.json" % map))
		var hv: Dictionary = recipe["power"]["high_voltage"]
		var lv: Dictionary = recipe["power"]["poles"]
		for circuits: Variant in cfg["pylon"]["choices"]["circuits"]:
			for height: Variant in cfg["pylon"]["choices"]["height"]:
				var p := VoxLatticePylon.new().with_defaults({"circuits": circuits, "height": height})
				# Its feet may stand that far below its middle on the steepest ground allowed.
				var drop := float(hv["max_grade"]) * float(p["base"]) / 2.0 * sqrt(2.0) + sink
				var ys := VoxLatticePylon.attach_points(p).map(func(a: Vector3) -> float: return a.y)
				assert_float(ys.min() - drop).override_failure_message("%s: pylon %s m, circuits %s" % [map, height, circuits]).is_greater_equal(float(hv["wire_height"]))
				assert_float(ys.max()).is_less_equal(float(hv["top_height"]))
				# Its terminal stands on the yard's pad, at least as high as the ground in it.
				var t := (cfg["terminal"]["params"] as Dictionary).duplicate()
				t["circuits"] = circuits
				var ts := VoxTerminalGantry.attach_points(t).map(func(a: Vector3) -> float: return a.y)
				assert_float(ts.min()).is_greater_equal(float(hv["wire_height"]))
				assert_float(ts.max()).is_less_equal(float(hv["top_height"]))
		for wires: Variant in cfg["pole"]["choices"]["wires"]:
			for height: Variant in cfg["pole"]["choices"]["height"]:
				var p := {"wires": wires, "height": height, "tap": 90.0}
				var ys := (VoxPowerPole.attach_points(p) + VoxPowerPole.tap_points(p)).map(func(a: Vector3) -> float: return a.y)
				assert_float(ys.min() - sink).override_failure_message("%s: pole %s m" % [map, height]).is_greater_equal(float(lv["wire_height"]))
				assert_float(ys.max()).is_less_equal(float(lv["top_height"]))


func test_the_same_lines_give_the_same_towers() -> void:
	var points: Array[Vector3] = [Vector3(5, 10, 3), Vector3(40, 10, -30), Vector3(80, 10, -50)]
	var a: Array = _plan([_line("low_voltage", "city", points)])["towers"]
	var b: Array = _plan([_line("low_voltage", "city", points)])["towers"]
	for i in a.size():
		assert_bool((a[i]["transform"] as Transform3D).is_equal_approx(b[i]["transform"])).is_true()
		assert_dict(b[i]["params"]).is_equal(a[i]["params"])

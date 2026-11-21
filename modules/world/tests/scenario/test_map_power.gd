extends GdUnitTestSuite
## Power lines on generated maps (#494), held to their rules over both shipped recipes and a
## few seeds: every town gets a high-voltage line from its own terminal in the substation
## yard, every foot keeps off water, roads, settlements and sites, spans keep to their ranges
## and pass over no settlement or site, lines cross only with room between their wires, pole
## lines stay set back from the roads, and the same seed gives the same lines. The scenery
## keeps trees out from under them, and missions are told the towers' ground is taken.

const SEEDS := [1, 2, 3]
const WORLD := "res://modules/world/data/world.json"

static var _worlds: Array[Dictionary] = []


func before() -> void:
	for map in ["grassland", "mixed"]:
		var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://modules/world/data/maps/%s.json" % map))
		for seed_value: int in SEEDS:
			var world := MapRender.build(recipe, seed_value)
			world["recipe"] = recipe
			world["seed"] = seed_value
			world["name"] = "%s seed %d" % [map, seed_value]
			_worlds.append(world)


func after() -> void:
	_worlds.clear()
	WorldMaps.clear()


func _lines(world: Dictionary, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line: Dictionary in (world["power"] as MapPower).lines():
		if line["kind"] == kind:
			out.append(line)
	return out


func _cfg(world: Dictionary, line: Dictionary) -> Dictionary:
	return world["recipe"]["power"]["high_voltage" if line["kind"] == "high_voltage" else "poles"]


func test_every_town_has_a_high_voltage_line_from_its_own_terminal() -> void:
	var lines := 0
	for world in _worlds:
		var places: Settlements = world["places"]
		if places.city().is_empty():
			continue
		var power: MapPower = world["power"]
		var station := power.substation()
		var fed: Array = _lines(world, "high_voltage").map(func(l: Dictionary) -> String: return str(l["to"]))
		for i in places.towns().size():
			assert_bool(fed.has("town %d" % i)).override_failure_message("%s: town %d has no line" % [world["name"], i]).is_true()
		var starts := {}
		for line in _lines(world, "high_voltage"):
			var first: Vector2 = (line["points"] as PackedVector2Array)[0]
			assert_str(str(line["from"])).is_equal("substation")
			assert_bool((station["yard"] as Rect2).has_point(first)).override_failure_message("%s: a line starts outside the yard" % world["name"]).is_true()
			assert_bool(starts.has(first)).override_failure_message("%s: two lines share a terminal" % world["name"]).is_false()
			starts[first] = true
		lines += fed.size()
	assert_int(lines).is_greater(3)


func test_a_tap_starts_on_a_pole_of_an_earlier_line() -> void:
	for world in _worlds:
		var all := (world["power"] as MapPower).lines()
		for i in all.size():
			var from := str(all[i]["from"])
			if not from.begins_with("line "):
				continue
			var parent := int(from.get_slice(" ", 1))
			assert_int(parent).is_less(i)
			assert_str(str(all[parent]["kind"])).is_equal("low_voltage")
			assert_bool((all[parent]["points"] as PackedVector2Array).has((all[i]["points"] as PackedVector2Array)[0])).is_true()


func test_feet_keep_off_water_roads_settlements_and_sites() -> void:
	var feet := 0
	for world in _worlds:
		var power: MapPower = world["power"]
		var places: Settlements = world["places"]
		var settled: Array[Rect2] = []
		for t: Dictionary in places.towns():
			settled.append(t["footprint"])
		if not places.city().is_empty():
			settled.append(places.city()["footprint"])
		var station := power.substation()
		for line: Dictionary in power.lines():
			var high: bool = line["kind"] == "high_voltage"
			var spec := _cfg(world, line)
			var foot := float(spec["foot"]) if high else MapPower.POLE_FOOT
			var gap := float(spec["keep_clear"]) + foot if high else float(spec["min_setback"]) + foot
			var points: PackedVector2Array = line["points"]
			for k in points.size():
				var p := points[k]
				# A terminal stands in the yard, which is checked as a whole.
				if high and k == 0:
					continue
				feet += 1
				var what := "%s: %s foot at %s" % [world["name"], line["kind"], p]
				# Dry under the whole foot, sampled finer than the placing does.
				for r: float in [0.0, foot * 0.5, foot]:
					for i in 16:
						var w := p + Vector2.from_angle(TAU * i / 16.0) * r
						assert_bool(is_nan(power.land.water_level(w.x, w.y))).override_failure_message(what + " in water").is_true()
				assert_float(power.works.road_distance(p.x, p.y)).override_failure_message(what + " on a road").is_greater_equal(gap - 0.01)
				for r in settled:
					assert_bool(r.has_point(p)).override_failure_message(what + " in a settlement").is_false()
				for s: Dictionary in (world["sites"] as MapSites).sites():
					assert_bool((s["footprint"] as Rect2).grow(foot).has_point(p)).override_failure_message(what + " on a site").is_false()
				if not station.is_empty():
					assert_bool((station["yard"] as Rect2).has_point(p)).override_failure_message(what + " in the yard").is_false()
				assert_float(power.works.grade(p.x, p.y)).override_failure_message(what + " too steep").is_less_equal(float(spec["max_grade"]) + 0.001)
		if not station.is_empty():
			var yard: Rect2 = station["yard"]
			for j in 5:
				for i in 5:
					var p := yard.position + yard.size * Vector2(i, j) / 4.0
					assert_bool(power.dry(p, 0.0)).override_failure_message("%s: the yard is in water" % world["name"]).is_true()
					assert_float(power.works.road_distance(p.x, p.y)).override_failure_message("%s: a road through the yard" % world["name"]).is_greater(0.0)
	assert_int(feet).is_greater(50)


func test_spans_keep_to_their_ranges_and_pass_over_no_settlement_or_site() -> void:
	for world in _worlds:
		var places: Settlements = world["places"]
		var over: Array[Rect2] = []
		for t: Dictionary in places.towns():
			over.append(t["footprint"])
		if not places.city().is_empty():
			over.append(places.city()["footprint"])
		for s: Dictionary in (world["sites"] as MapSites).sites():
			over.append(s["footprint"])
		for line: Dictionary in (world["power"] as MapPower).lines():
			var range_of: Array = _cfg(world, line)["span"]
			var points: PackedVector2Array = line["points"]
			assert_int(points.size()).is_greater_equal(2)
			for k in range(1, points.size()):
				var length := points[k].distance_to(points[k - 1])
				var what := "%s: %s to %s span %d (%.0f m)" % [world["name"], line["from"], line["to"], k, length]
				assert_float(length).override_failure_message(what + " too long").is_less_equal(float(range_of[1]) + 0.01)
				# A town nearer its terminal than a span is one short span.
				if points.size() > 2:
					assert_float(length).override_failure_message(what + " too short").is_greater_equal(float(range_of[0]) - 0.01)
				for r in over:
					assert_bool(MapPower.segment_meets(r, points[k - 1], points[k])).override_failure_message(what + " over " + str(r)).is_false()


func test_lines_cross_only_with_room_between_their_wires() -> void:
	for world in _worlds:
		var power: MapPower = world["power"]
		var margin := float(world["recipe"]["power"]["crossing_clearance"])
		var spans: Array[Array] = []
		for i in power.lines().size():
			var line: Dictionary = power.lines()[i]
			var pts: PackedVector2Array = line["points"]
			for k in range(1, pts.size()):
				spans.append([pts[k - 1], pts[k], i, _cfg(world, line)])
		for x in spans.size():
			for y in range(x + 1, spans.size()):
				var a: Array = spans[x]
				var b: Array = spans[y]
				if a[2] == b[2] or a[0] == b[0] or a[0] == b[1] or a[1] == b[0] or a[1] == b[1]:
					continue
				var hit: Variant = Geometry2D.segment_intersects_segment(a[0], a[1], b[0], b[1])
				if hit == null:
					continue
				var ha := _wires_at(power, a, hit)
				var hb := _wires_at(power, b, hit)
				var room := maxf(ha.x - hb.y, hb.x - ha.y)
				assert_float(room).override_failure_message("%s: lines %d and %d cross at %s with %.1f m between" % [world["name"], a[2], b[2], hit, room]).is_greater_equal(margin - 0.01)


## The lowest and highest wire of span [a, b, line, cfg] where it passes over `at`.
func _wires_at(power: MapPower, span: Array, at: Vector2) -> Vector2:
	var a: Vector2 = span[0]
	var b: Vector2 = span[1]
	var cfg: Dictionary = span[3]
	var t := a.distance_to(at) / a.distance_to(b)
	var ground := lerpf(power.works.height(a.x, a.y), power.works.height(b.x, b.y), t)
	var dip := 4.0 * float(cfg["sag"]) * a.distance_to(b) * t * (1.0 - t)
	return Vector2(ground + float(cfg["wire_height"]) - dip, ground + float(cfg["top_height"]) - dip)


func test_pole_lines_stay_set_back_from_the_roads() -> void:
	var poles := 0
	for world in _worlds:
		var power: MapPower = world["power"]
		var cfg: Dictionary = world["recipe"]["power"]["poles"]
		for line in _lines(world, "low_voltage"):
			for p: Vector2 in line["points"]:
				poles += 1
				assert_float(power.works.road_distance(p.x, p.y)).override_failure_message("%s: pole at %s" % [world["name"], p]).is_greater_equal(float(cfg["min_setback"]) - 0.01)
			# Beside a road most of the way, not out across the fields.
			var near := 0
			for p: Vector2 in line["points"]:
				if power.works.road_distance(p.x, p.y) <= float(cfg["setback"]) + 4.0:
					near += 1
			assert_float(float(near) / (line["points"] as PackedVector2Array).size()).override_failure_message("%s: pole line to %s strays" % [world["name"], line["to"]]).is_greater(0.5)
	assert_int(poles).is_greater(30)


func test_the_same_seed_gives_the_same_lines() -> void:
	var world := _worlds[0]
	var again := MapRender.build(world["recipe"], int(world["seed"]))
	var a := (world["power"] as MapPower).lines()
	var b := (again["power"] as MapPower).lines()
	assert_int(b.size()).is_equal(a.size())
	for i in a.size():
		assert_str(str(b[i]["from"])).is_equal(str(a[i]["from"]))
		assert_array(Array(b[i]["points"])).is_equal(Array(a[i]["points"]))


func test_tower_ground_counts_as_taken() -> void:
	WorldMaps.select("grassland", 1)
	var map := WorldMaps.shape()
	var towers := 0
	for line in map.power_lines():
		for p: Vector3 in line["points"]:
			towers += 1
			assert_bool(map.power_within(p.x, p.z, 1.0)).is_true()
	assert_int(towers).is_greater(10)
	var station := map.power_substation()
	assert_bool(station.is_empty()).is_false()
	var c: Vector3 = station["centre"]
	assert_bool(map.power_within(c.x, c.z, 0.0)).is_true()
	assert_bool(map.power_within(map.camp().x, map.camp().z, 5.0)).is_false()


func test_the_scenery_keeps_trees_out_from_under_the_whole_lines() -> void:
	WorldMaps.select("grassland", 1)
	var map := WorldMaps.shape()
	var lines := map.power_lines()
	assert_int(lines.size()).is_greater(0)
	var s := SceneryScatter.new()
	s.set(&"_visual", false)
	add_child(s)
	s.set_process(false)
	var clearance: Dictionary = (Data.load_json(WORLD) as Dictionary)["scatter"]["power_clearance"]
	# Every chunk any span passes over, not just those the towers stand in.
	var chunks := {}
	for line in lines:
		var points: Array = line["points"]
		for k in range(1, points.size()):
			var a: Vector3 = points[k - 1]
			var b: Vector3 = points[k]
			var steps := ceili(a.distance_to(b) / 8.0)
			for i in steps + 1:
				var p := a.lerp(b, float(i) / steps)
				chunks[s.chunk_at(p.x, p.z)] = true
	var checked := 0
	for chunk: int in chunks:
		var plan := s.plan_chunk(chunk, [] as Array[Vector3])
		for kind: String in ["trees", "rocks"]:
			for thing: Dictionary in plan[kind]:
				var at: Vector3 = (thing["xform"] as Transform3D).origin
				var here := Vector2(at.x, at.z)
				checked += 1
				for line in lines:
					var points: Array = line["points"]
					var corridor := float(clearance[line["kind"]])
					for k in range(1, points.size()):
						var a := Vector2((points[k - 1] as Vector3).x, (points[k - 1] as Vector3).z)
						var b := Vector2((points[k] as Vector3).x, (points[k] as Vector3).z)
						var d := here.distance_to(Geometry2D.get_closest_point_to_segment(here, a, b))
						assert_float(d).override_failure_message("%s at %s under a %s line" % [kind, here, line["kind"]]).is_greater_equal(corridor)
	assert_int(checked).is_greater(50)
	s.queue_free()

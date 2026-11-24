extends GdUnitTestSuite
## Roads and settlements shape the land (#428): the road surface is the shaped ground, banks
## are no steeper than the recipe allows, settlements stand on level pads, and land away
## from them is untouched.

const SEED := 1

static var _works: Earthworks
static var _net: RoadNetwork
static var _places: Settlements
static var _cfg: Dictionary


func before() -> void:
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://modules/world/data/maps/grassland.json"))
	var land := WorldLand.new(recipe, SEED)
	var zones := LandZones.new(land, recipe["zones"])
	_places = Settlements.new(zones, recipe["settlements"])
	_net = RoadNetwork.new(_places, recipe["roads"])
	_cfg = recipe["earthworks"]
	_works = Earthworks.new(land, _places, _net, _cfg)


func test_there_are_roads_to_shape() -> void:
	assert_int(_net.roads().size()).is_greater(0)


func test_the_ground_is_at_road_height_along_every_road() -> void:
	for road: Dictionary in _net.roads():
		var points: PackedVector2Array = road["points"]
		var heights: PackedFloat32Array = road["heights"]
		var skip := _spans(road)
		for i in points.size():
			if skip.has(i):
				continue
			var p := points[i]
			assert_float(_works.height(p.x, p.y)).override_failure_message("%s at %d" % [road["from"], i]).is_equal_approx(heights[i], 0.05)


func test_banks_are_never_steeper_than_the_recipe_allows() -> void:
	var bank := float(_cfg["bank_grade"])
	var reach := float(_cfg["reach"])
	var shoulder := float(_cfg["shoulder"])
	var checked := 0
	for road: Dictionary in _net.roads():
		var points: PackedVector2Array = road["points"]
		var skip := _spans(road)
		var half := float(road["width"]) / 2.0 + shoulder
		for i in range(2, points.size() - 2, 5):
			if skip.has(i) or skip.has(i - 1) or skip.has(i + 1):
				continue
			var across := (points[i + 1] - points[i - 1]).normalized().orthogonal()
			for side: float in [-1.0, 1.0]:
				# Out to where banks start easing into the land (the last quarter of the reach).
				var out := 0.0
				while out + 1.0 < reach * 0.75:
					var a := points[i] + across * side * (half + out)
					var b := points[i] + across * side * (half + out + 1.0)
					out += 1.0
					# Only on the bank itself, where this road is the only work.
					if _near_other_work(b, road) or _works.height(a.x, a.y) == _works.land.height(a.x, a.y) or _works.height(b.x, b.y) == _works.land.height(b.x, b.y):
						continue
					checked += 1
					var rise := absf(_works.height(b.x, b.y) - _works.height(a.x, a.y))
					# Across a climbing road the bank also climbs with it: the steepest it can be
					# is the bank and the road's own grade together.
					assert_float(rise).override_failure_message("%s at %d, %.0f m out" % [road["from"], i, out]).is_less_equal(bank + float(road["max_grade"]) + 0.02)
	# Enough bank to judge: the island's lowland (#454) needs fewer, lower cuts than the
	# square map did.
	assert_int(checked).is_greater(50)


func test_the_land_over_a_tunnel_and_under_a_bridge_is_left_alone() -> void:
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://modules/world/data/maps/mixed.json"))
	var spans := 0
	for seed_value in [3, 1, 2]:
		var land := WorldLand.new(recipe, seed_value)
		var places := Settlements.new(LandZones.new(land, recipe["zones"]), recipe["settlements"])
		var net := RoadNetwork.new(places, recipe["roads"])
		var works := Earthworks.new(land, places, net, recipe["earthworks"])
		for road: Dictionary in net.roads():
			var points: PackedVector2Array = road["points"]
			for span: Vector2i in (road["tunnels"] as Array) + (road["bridges"] as Array):
				spans += 1
				for i in range(span.x, span.y + 1):
					var p := points[i]
					# Another road or a settlement may still shape it: only where no other road
					# comes within its earthworks' reach.
					if _other_road_near(net, road, p, float(recipe["earthworks"]["reach"]) + 10.0):
						continue
					assert_float(works.height(p.x, p.y)).override_failure_message("seed %d %s at %d" % [seed_value, road["from"], i]).is_equal(land.height(p.x, p.y))
		if spans > 0:
			break
	assert_int(spans).is_greater(0)


func test_settlements_stand_on_level_pads() -> void:
	var all: Array[Dictionary] = _places.towns().duplicate()
	all.append(_places.city())
	for place in all:
		var foot: Rect2 = place["footprint"]
		for i in 4:
			for j in 4:
				var p := foot.position + foot.size * (Vector2(i, j) + Vector2(0.5, 0.5)) / 4.0
				assert_float(_works.height(p.x, p.y)).is_equal_approx(float(place["level"]), 0.01)


func test_land_away_from_every_work_is_untouched() -> void:
	var b := _works.land.bounds()
	var reach := float(_cfg["reach"])
	var checked := 0
	for j in 16:
		for i in 16:
			var p := b.position + b.size * (Vector2(i, j) + Vector2(0.5, 0.5)) / 16.0
			if _within(p, reach + 40.0):
				continue
			checked += 1
			assert_float(_works.height(p.x, p.y)).is_equal(_works.land.height(p.x, p.y))
	assert_int(checked).is_greater(50)


static func _spans(road: Dictionary) -> Dictionary:
	var out := {}
	for span: Vector2i in (road["tunnels"] as Array) + (road["bridges"] as Array):
		for i in range(span.x - 1, span.y + 2):
			out[i] = true
	return out


## Whether a road other than `road`, or a settlement, comes within the reach of `p`.
func _near_other_work(p: Vector2, road: Dictionary) -> bool:
	var reach := float(_cfg["reach"]) + 20.0
	for other: Dictionary in _net.roads():
		if other == road:
			continue
		for q: Vector2 in other["points"]:
			if q.distance_to(p) < reach:
				return true
	var all: Array[Dictionary] = _places.towns().duplicate()
	all.append(_places.city())
	return all.any(func(s: Dictionary) -> bool: return (s["footprint"] as Rect2).grow(reach).has_point(p))


func _within(p: Vector2, distance: float) -> bool:
	for road: Dictionary in _net.roads():
		for q: Vector2 in road["points"]:
			if q.distance_to(p) < distance:
				return true
	var all: Array[Dictionary] = _places.towns().duplicate()
	all.append(_places.city())
	return all.any(func(s: Dictionary) -> bool: return (s["footprint"] as Rect2).grow(distance).has_point(p))


func _other_road_near(net: RoadNetwork, road: Dictionary, p: Vector2, within: float) -> bool:
	for other: Dictionary in net.roads():
		if other == road:
			continue
		for q: Vector2 in other["points"]:
			if q.distance_to(p) < within:
				return true
	return false


func test_a_road_winding_back_past_a_tunnel_still_shapes_its_own_ground() -> void:
	# A tunnel running north from (0, 0) to (0, 100), its mouths facing into it; the road it is
	# part of comes back past it 40 m to the east, between the mouths' planes.
	var span := PackedVector2Array([Vector2(0, -4), Vector2(0, 1), Vector2(0, 104), Vector2(0, -1), Vector2(-70, -70), Vector2(70, 170)])
	span.append_array(PackedVector2Array([Vector2(0, -4), Vector2(0, 0), Vector2(0, 50), Vector2(0, 100), Vector2(0, 104)]))
	var road := {"slabs": [span]}
	# Over the tunnel: nearer the span than any segment of the road asking.
	assert_bool(Earthworks._in_span(road, Vector2(2, 50), 40.0)).is_true()
	# Beside the road where it comes back: its own segment is nearer than the span.
	assert_bool(Earthworks._in_span(road, Vector2(38, 50), 2.0)).is_false()
	# Outside the mouths' planes: never the span's.
	assert_bool(Earthworks._in_span(road, Vector2(2, -20), 40.0)).is_false()

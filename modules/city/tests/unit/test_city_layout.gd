extends GdUnitTestSuite
## A European city's plan: perimeter blocks (one building along each side of a courtyard,
## a gateway through each street front) between streets that aren't quite a grid, wider
## streets round an open square in the middle, a little taller toward it; lamps, street
## trees and zebra crossings along the streets, clear of doors, gateways and each other; the
## same for the same seed.

const CFG := {
	"size": 150.0, "blocks": 3, "street_width": 8.0, "avenue_width": 10.0, "street_jitter": 2.0, "pavement": 3.0,
	"passage_width": 3.0, "gateway_height": 3.2, "building_depth": 9.5, "floors_edge": 4, "floors_middle": 6, "style": "danish",
	"crossing_width": 3.0, "crossing_setback": 0.6, "lamp_spacing": 25.0, "lamp_inset": 0.5,
	"tree_spacing": 12.0, "tree_inset": 1.1, "tree_street_width": 10.0, "door_clear": 2.0, "spot_nudge": 3.0,
}


func _plan(seed := 5) -> Dictionary:
	return CityLayout.make(CFG, seed)


func _non_square_blocks(p: Dictionary) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for block: Rect2 in p["blocks"]:
		if not (p["squares"] as Array).has(block):
			out.append(block)
	return out


func test_same_seed_same_city() -> void:
	assert_str(var_to_str(_plan(5))).is_equal(var_to_str(_plan(5)))
	assert_str(var_to_str(_plan(5))).is_not_equal(var_to_str(_plan(6)))


func test_streets_ring_and_cross_it_not_quite_a_grid() -> void:
	var p := _plan()
	assert_int((p["streets"] as Array).size()).is_equal(8)
	var sizes: Array[float] = []
	for block: Rect2 in p["blocks"]:
		sizes.append(snappedf(block.size.x, 0.01))
		for street: Rect2 in p["streets"]:
			# Edges meet exactly; a centimetre in keeps float rounding out of it.
			assert_bool(block.grow(-0.01).intersects(street)).is_false()
	# Nudged street lines: blocks aren't all the same width.
	assert_int(sizes.filter(func(s: float) -> bool: return not is_equal_approx(s, sizes[0])).size()).is_greater(0)


func test_the_streets_round_the_square_are_wider() -> void:
	var p := _plan()
	var square: Rect2 = p["squares"][0]
	for street: Rect2 in p["streets"]:
		var width := minf(street.size.x, street.size.y)
		var by_square := street.grow(0.01).intersects(square)
		assert_float(width).is_equal_approx(10.0 if by_square else 8.0, 0.001)


func test_the_middle_block_is_an_open_square() -> void:
	var p := _plan()
	assert_int((p["squares"] as Array).size()).is_equal(1)
	var square: Rect2 = p["squares"][0]
	assert_bool(square.has_point(Vector2.ZERO)).is_true()
	for b: Dictionary in p["buildings"]:
		assert_bool((b["footprint"] as Rect2).intersects(square)).is_false()


func test_one_building_along_each_side_of_every_block() -> void:
	for seed in [1, 5, 9, 23]:
		var p := _plan(seed)
		var buildings: Array = p["buildings"]
		for block in _non_square_blocks(p):
			var inside := buildings.filter(func(b: Dictionary) -> bool: return block.encloses(b["footprint"]))
			assert_int(inside.size()).is_equal(4)
			var facings: Array[Vector2] = []
			for b: Dictionary in inside:
				facings.append(b["facing"])
			for f: Vector2 in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
				assert_bool(facings.has(f)).is_true()
		# Blocks closed all round: the four together cover the block's ring, corners included.
		assert_int(buildings.size()).is_equal(8 * 4)


func test_buildings_stand_wall_to_wall_off_the_streets_and_yards() -> void:
	var p := _plan()
	var feet: Array[Rect2] = []
	for b: Dictionary in p["buildings"]:
		var foot: Rect2 = b["footprint"]
		for other in feet:
			assert_bool(foot.grow(-0.01).intersects(other)).is_false()
		feet.append(foot)
		for street: Rect2 in p["streets"]:
			assert_bool(foot.grow(-0.01).intersects(street)).is_false()
		for yard: Rect2 in p["yards"]:
			assert_bool(foot.grow(-0.01).intersects(yard)).is_false()
		# A step out of each front door is on the pavement, not in the courtyard.
		for out: Vector2 in b["doors"]:
			var on_pavement := false
			for block: Rect2 in p["blocks"]:
				on_pavement = on_pavement or (block.has_point(out) and not block.grow(-float(CFG["pavement"])).has_point(out))
			assert_bool(on_pavement).is_true()


func test_each_street_front_has_a_gateway_into_its_courtyard() -> void:
	var p := _plan()
	var passages: Array = p["passages"]
	# Two street fronts on each of the eight blocks.
	assert_int(passages.size()).is_equal(16)
	for passage: Rect2 in passages:
		assert_float(minf(passage.size.x, passage.size.y)).is_equal_approx(3.0, 0.01)
		var front: Array = (p["buildings"] as Array).filter(func(b: Dictionary) -> bool: return (b["footprint"] as Rect2).grow(0.01).encloses(passage))
		assert_int(front.size()).is_equal(1)
		var b: Dictionary = front[0]
		assert_bool((b["facing"] as Vector2).x == 0.0).is_true()
		assert_float(passage.size.y).is_equal_approx((b["footprint"] as Rect2).size.y, 0.01)
		assert_float(float((b["params"] as Dictionary)["gateway"])).is_equal(1.0)
		# It opens onto the courtyard, not onto the end of a side building.
		var into_yard := false
		for yard: Rect2 in p["yards"]:
			into_yard = into_yard or (passage.position.x >= yard.position.x - 0.01 and passage.end.x <= yard.end.x + 0.01 and passage.grow(0.05).intersects(yard))
		assert_bool(into_yard).is_true()
		# And no front door opens into it.
		for door: Vector2 in b["doors"]:
			assert_bool(passage.grow(0.5).has_point(door)).is_false()


func test_neighbouring_fronts_never_share_a_wall_colour() -> void:
	for seed in [1, 5, 9, 23]:
		var p := _plan(seed)
		var buildings: Array = p["buildings"]
		var used := {}
		for i in buildings.size():
			var a: Dictionary = buildings[i]
			var wa := int((a["params"] as Dictionary)["walls"])
			used[wa] = true
			for j in i:
				var b: Dictionary = buildings[j]
				var wb := int((b["params"] as Dictionary)["walls"])
				var fa: Rect2 = a["footprint"]
				var fb: Rect2 = b["footprint"]
				# Touching at a corner, or the next front along the same side of a street.
				var touching := fa.grow(0.05).intersects(fb)
				var along: bool = a["facing"] == b["facing"] and fa.grow(8.0).intersects(fb.grow(8.0))
				if touching or along:
					assert_int(wa).is_not_equal(wb)
		# Brick and render both turn up.
		assert_int(used.size()).is_greater_equal(4)


func test_a_little_taller_toward_the_middle() -> void:
	var p := _plan()
	var inner: Array[float] = []
	var outer: Array[float] = []
	for b: Dictionary in p["buildings"]:
		var at := (b["footprint"] as Rect2).get_center().length()
		var floors := float((b["params"] as Dictionary)["floors"])
		if at < 40.0:
			inner.append(floors)
		elif at > 58.0:
			outer.append(floors)
		assert_float(floors).is_between(3.0, 6.0)
	var mean := func(list: Array[float]) -> float:
		var sum := 0.0
		for f in list:
			sum += f
		return sum / maxf(list.size(), 1.0)
	assert_float(float(mean.call(inner))).is_greater(float(mean.call(outer)))


func test_buildings_fill_their_plots_wall_to_wall() -> void:
	for b: Dictionary in _plan()["buildings"]:
		var params: Dictionary = b["params"]
		var length := float(params["stairwells"]) * (float(params["flat_width"]) * 2.0 + CityLayout.STAIR_BAY)
		var foot: Rect2 = b["footprint"]
		assert_float(length).is_equal_approx(maxf(foot.size.x, foot.size.y), 0.01)
		assert_float(float(params["flat_width"])).is_between(4.5, 7.5)


func test_zebra_crossings_at_every_junction_between_blocks() -> void:
	var p := _plan()
	var crossings: Array = p["crossings"]
	# Two inner streets each way, each meeting four lines across: one arm at a ring street,
	# two at an inner one, so 2 x 2 x (1 + 2 + 2 + 1).
	assert_int(crossings.size()).is_equal(24)
	for c: Rect2 in crossings:
		var on: Array = (p["streets"] as Array).filter(func(s: Rect2) -> bool: return s.grow(0.01).encloses(c))
		assert_int(on.size()).is_greater_equal(1)
		# Kerb to kerb across the street it crosses, its own width along it.
		assert_float(minf(c.size.x, c.size.y)).is_equal_approx(3.0, 0.01)
		# Between two blocks: pavement on both ends.
		var ends := 0
		for block: Rect2 in p["blocks"]:
			if c.grow(0.05).intersects(block):
				ends += 1
		assert_int(ends).is_equal(2)


func _keep_clear(p: Dictionary, at: Vector2, label: String) -> void:
	for b: Dictionary in p["buildings"]:
		for door: Vector2 in b["doors"]:
			assert_float(at.distance_to(door)).override_failure_message("%s at %s blocks a door at %s" % [label, at, door]).is_greater_equal(1.5)
	for passage: Rect2 in p["passages"]:
		assert_bool(passage.grow(1.0).has_point(at)).override_failure_message("%s at %s blocks a gateway" % [label, at]).is_false()
	for c: Rect2 in p["crossings"]:
		assert_bool(c.grow(1.0).has_point(at)).override_failure_message("%s at %s blocks a crossing" % [label, at]).is_false()


## Spots along each block edge, in order, keyed by edge.
func _by_edge(p: Dictionary, spots: Array[Vector2], inset: float) -> Dictionary:
	var out := {}
	for at in spots:
		for i in (p["blocks"] as Array).size():
			var block: Rect2 = p["blocks"][i]
			if not block.has_point(at):
				continue
			var edges := {
				Vector2(0, -1): at.y - block.position.y, Vector2(0, 1): block.end.y - at.y,
				Vector2(-1, 0): at.x - block.position.x, Vector2(1, 0): block.end.x - at.x,
			}
			for f: Vector2 in edges:
				if is_equal_approx(float(edges[f]), inset):
					var key := "%d %s" % [i, f]
					if not out.has(key):
						out[key] = []
					(out[key] as Array).append(at.x if f.x == 0.0 else at.y)
	for key: String in out:
		(out[key] as Array).sort()
	return out


func test_street_lamps_on_both_sides_staggered_and_spaced() -> void:
	var p := _plan()
	var lamps: Array = p["lamps"]
	assert_int(lamps.size()).is_greater(30)
	var spots: Array[Vector2] = []
	for lamp: Dictionary in lamps:
		var at: Vector2 = lamp["at"]
		spots.append(at)
		_keep_clear(p, at, "lamp")
		# Its arm reaches out over the street it stands beside.
		var out: Vector2 = lamp["out"]
		var over := at + out * 2.0
		var on_street := false
		for s: Rect2 in p["streets"]:
			on_street = on_street or s.has_point(over)
		assert_bool(on_street).is_true()
	var edges := _by_edge(p, spots, 0.5)
	for key: String in edges:
		var along: Array = edges[key]
		for i in range(1, along.size()):
			assert_float(float(along[i]) - float(along[i - 1])).is_greater_equal(25.0 - 2.0 * 3.0)
	# Both sides of an inner street, not opposite each other.
	var street: Rect2 = p["streets"][2]
	var west: Array[float] = []
	var east: Array[float] = []
	for at in spots:
		if absf(at.x - (street.position.x - 0.5)) < 0.01:
			west.append(at.y)
		elif absf(at.x - (street.end.x + 0.5)) < 0.01:
			east.append(at.y)
	assert_int(west.size()).is_greater(1)
	assert_int(east.size()).is_greater(1)
	var opposite := 0
	for y in west:
		for y2 in east:
			if absf(y - y2) < 4.0:
				opposite += 1
	assert_int(opposite).is_less(west.size())


func test_street_trees_in_grates_along_the_wider_streets_only() -> void:
	var p := _plan()
	var trees: Array = p["trees"]
	assert_int(trees.size()).is_greater(10)
	var lamps: Array = p["lamps"]
	var spots: Array[Vector2] = []
	for at: Vector2 in trees:
		spots.append(at)
		_keep_clear(p, at, "tree")
		for lamp: Dictionary in lamps:
			assert_float(at.distance_to(lamp["at"])).is_greater_equal(2.0)
		# The street beside it is a wide one.
		var beside: Array = (p["streets"] as Array).filter(func(s: Rect2) -> bool: return s.grow(1.2).has_point(at))
		assert_int(beside.size()).is_greater_equal(1)
		for s: Rect2 in beside:
			assert_float(minf(s.size.x, s.size.y)).is_greater_equal(10.0)
	for key: String in _by_edge(p, spots, 1.1):
		var along: Array = _by_edge(p, spots, 1.1)[key]
		for i in range(1, along.size()):
			assert_float(float(along[i]) - float(along[i - 1])).is_greater_equal(12.0 - 2.0 * 3.0)


func test_street_fronts_keep_their_balconies_flush_where_the_sides_butt_on() -> void:
	for b: Dictionary in _plan()["buildings"]:
		var params: Dictionary = b["params"]
		if (b["facing"] as Vector2).x == 0.0:
			assert_float(float(params["balconies"])).is_equal(3.0)


const HANDMADE := [
	{"name": "plaza", "size": Vector2(33, 33), "tags": ["square"], "markers": []},
	{"name": "yard_a", "size": Vector2(32, 32), "tags": ["residential"], "markers": [{"kind": "door", "at": Vector3(0, 0, -16), "yaw": 0.0}, {"kind": "spawn", "at": Vector3(2, 0, 2), "yaw": 0.0}]},
	{"name": "yard_b", "size": Vector2(32, 32), "tags": ["ruin"], "markers": []},
]


func _with_handmade(seed := 5, share := 1.0) -> Dictionary:
	var cfg := CFG.duplicate()
	cfg["handmade_share"] = share
	cfg["handmade_slack"] = 6.0
	return CityLayout.make(cfg, seed, HANDMADE)


func test_the_square_takes_a_square_block() -> void:
	var p := _with_handmade(5, 0.0)
	var placed: Array = p["handmade"]
	assert_int(placed.size()).is_equal(1)
	assert_str(str(placed[0]["name"])).is_equal("plaza")
	assert_bool((placed[0]["rect"] as Rect2).has_point(Vector2.ZERO)).is_true()


func test_hand_made_blocks_replace_generated_ones_and_never_repeat_side_by_side() -> void:
	var p := _with_handmade(5, 1.0)
	var placed: Array = p["handmade"]
	assert_int(placed.size()).is_equal(9)
	for h: Dictionary in placed:
		var r: Rect2 = h["rect"]
		for b: Dictionary in p["buildings"]:
			assert_bool((b["footprint"] as Rect2).grow(-0.01).intersects(r)).is_false()
		for other: Dictionary in placed:
			if other == h or str(other["name"]) != str(h["name"]):
				continue
			# Neighbours share an edge (a street between them): never the same block.
			var gap := (r.get_center() - (other["rect"] as Rect2).get_center()).abs()
			# In line (one offset near zero) and one block apart (under 60 m), not two.
			var adjacent := minf(gap.x, gap.y) < 1.0 and maxf(gap.x, gap.y) < 60.0
			assert_bool(adjacent).override_failure_message("%s next to itself" % h["name"]).is_false()


func test_without_hand_made_blocks_nothing_changes() -> void:
	var cfg := CFG.duplicate()
	assert_str(var_to_str(CityLayout.make(cfg, 5))).is_equal(var_to_str(CityLayout.make(cfg, 5, [])))

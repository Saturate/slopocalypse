extends GdUnitTestSuite
## A European city's plan: perimeter blocks (buildings wall to wall round all four sides of
## a courtyard, a passage through) between streets that aren't quite a grid, an open square
## in the middle, a little taller toward it; the same for the same seed.

const CFG := {"size": 150.0, "blocks": 3, "street_width": 8.0, "street_jitter": 4.0, "pavement": 3.0, "passage_width": 3.0, "building_depth": 10.0, "floors_edge": 4, "floors_middle": 6, "style": "danish"}


func _plan(seed := 5) -> Dictionary:
	return CityLayout.make(CFG, seed)


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


func test_the_middle_block_is_an_open_square() -> void:
	var p := _plan()
	assert_int((p["squares"] as Array).size()).is_equal(1)
	var square: Rect2 = p["squares"][0]
	assert_bool(square.has_point(Vector2.ZERO)).is_true()
	for b: Dictionary in p["buildings"]:
		assert_bool((b["footprint"] as Rect2).intersects(square)).is_false()


func test_perimeter_blocks_wall_to_wall_round_a_courtyard() -> void:
	var p := _plan()
	var buildings: Array = p["buildings"]
	# Eight blocks, two buildings on each street front and one on most sides.
	assert_int(buildings.size()).is_greater_equal(8 * 4)
	var feet: Array[Rect2] = []
	for b: Dictionary in buildings:
		var foot: Rect2 = b["footprint"]
		for other in feet:
			assert_bool(foot.grow(-0.01).intersects(other)).is_false()
		feet.append(foot)
		for street: Rect2 in p["streets"]:
			assert_bool(foot.grow(-0.01).intersects(street)).is_false()
		for yard: Rect2 in p["yards"]:
			assert_bool(foot.grow(-0.01).intersects(yard)).is_false()
		# A step out of the front door is on the pavement, not in the courtyard.
		var out: Vector2 = b["door_out"]
		var on_pavement := false
		for block: Rect2 in p["blocks"]:
			var ring := block
			on_pavement = on_pavement or (ring.has_point(out) and not ring.grow(-float(CFG["pavement"])).has_point(out))
		assert_bool(on_pavement).is_true()


func test_every_block_has_a_passage_through_to_its_courtyard() -> void:
	var p := _plan()
	assert_int((p["passages"] as Array).size()).is_equal(8)
	for passage: Rect2 in p["passages"]:
		assert_float(minf(passage.size.x, passage.size.y)).is_greater_equal(3.0)
		for b: Dictionary in p["buildings"]:
			assert_bool((b["footprint"] as Rect2).grow(-0.01).intersects(passage)).is_false()


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

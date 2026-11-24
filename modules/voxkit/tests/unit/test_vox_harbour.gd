extends GdUnitTestSuite
## The harbour and store pieces (#575): the jetty grows by whole sections and stays walkable
## end to end, the boat has an open floor to stand on inside its sides, the warehouse and
## shed take their size from their parameters, and every piece's collision is boxes that
## sit on what is drawn.


## Whether `point` is inside any of `boxes`.
func _inside(boxes: Array[AABB], point: Vector3) -> bool:
	for b in boxes:
		if b.grow(0.001).has_point(point):
			return true
	return false


## The highest box top under (x, z) and no higher than `below` (under a roof), or -1 when
## nothing is there.
func _ground(boxes: Array[AABB], x: float, z: float, below := INF) -> float:
	var top := -1.0
	for b in boxes:
		if b.end.y <= below and x >= b.position.x and x <= b.end.x and z >= b.position.z and z <= b.end.z:
			top = maxf(top, b.end.y)
	return top


func test_every_harbour_piece_has_its_own_boxes_and_they_fit_the_model() -> void:
	var pieces: Array[VoxGenerator] = [VoxJetty.new(), VoxBoatShed.new(), VoxHarbourProp.new(), VoxBoat.new(), VoxWarehouse.new(), VoxShelving.new(), VoxFlatPack.new()]
	for gen in pieces:
		var variants: Array[Dictionary] = [{}]
		# Every slider at its low end, and at its high end with the finest voxel: the
		# biggest grid, which must not hit the cap and shrink.
		for end: String in ["min", "max"]:
			var ends := {}
			for spec in gen.params():
				ends[spec["key"]] = spec["min"] if spec["key"] == "voxel" else spec[end]
			variants.append(ends)
		if gen is VoxHarbourProp:
			for kind in VoxHarbourProp.KINDS.size():
				variants.append({"kind": float(kind)})
		for values in variants:
			var boxes: Array[AABB] = gen.call(&"collision", values)
			var name := "%s %s" % [gen.title(), values]
			assert_int(boxes.size()).override_failure_message(name + " has no collision").is_greater(0)
			var model := gen.build(values)
			var cells := model.cells()
			var v := model.voxel_size()
			var grid := AABB(Vector3(-cells.x * v / 2.0, 0.0, -cells.z * v / 2.0), Vector3(cells) * v).grow(v)
			for b in boxes:
				assert_bool(b.size.x > 0.0 and b.size.y > 0.0 and b.size.z > 0.0).override_failure_message("%s: empty box %s" % [name, b]).is_true()
				assert_bool(grid.encloses(b)).override_failure_message("%s: box %s outside the model %s" % [name, b, grid]).is_true()


func test_the_jetty_grows_by_whole_sections() -> void:
	var jetty := VoxJetty.new()
	for sections in [1, 4, 9]:
		var values := {"sections": float(sections), "voxel": 0.1}
		assert_float(VoxJetty.length(values)).is_equal_approx(sections * VoxJetty.SECTION, 0.001)
		var boxes := VoxJetty.collision(values)
		# The deck spans the whole length.
		assert_float(boxes[0].size.z).is_equal_approx(sections * VoxJetty.SECTION, 0.001)
		# Two piles at every joint.
		var piles := boxes.filter(func(b: AABB) -> bool: return is_zero_approx(b.position.y) and b.size.x < 0.5 and b.size.z < 0.5)
		# The ladder stands on the sea bed too but is wider than a pile.
		assert_int(piles.size()).is_equal((sections + 1) * 2)
	var short := jetty.build({"sections": 2.0, "voxel": 0.1}).voxel_count()
	var long := jetty.build({"sections": 6.0, "voxel": 0.1}).voxel_count()
	assert_int(long).is_greater(short * 2)


func test_the_jetty_deck_is_walkable_end_to_end() -> void:
	var values := {"sections": 5.0, "width": 2.4, "height": 2.0}
	var boxes := VoxJetty.collision(values)
	var half := VoxJetty.length(values) / 2.0
	var z := -half + 0.1
	while z < half - 0.1:
		# Down the middle, the ground is the deck top and nothing stands on it.
		assert_float(_ground(boxes, 0.0, z)).is_equal_approx(VoxJetty.deck_top(values), 0.001)
		assert_bool(_inside(boxes, Vector3(0.0, 2.5, z))).is_false()
		z += 0.25
	# The ladder reaches from the sea bed to over the deck, facing back to shore.
	var climb := VoxJetty.ladder_box(values)
	assert_float(climb.position.y).is_equal(0.0)
	assert_float(climb.end.y).is_greater(VoxJetty.deck_top(values))
	assert_float(climb.position.z).is_greater_equal(half)
	assert_bool(VoxJetty.ladder_box({"ladder": 0.0}).has_volume()).is_false()


func test_the_boat_has_a_floor_to_stand_on_inside_its_sides() -> void:
	for values: Dictionary in [{}, {"length": 5.0, "beam": 2.0}, {"length": 8.0, "beam": 3.0}]:
		var area := VoxBoat.deck_area(values)
		assert_float(area.end.y).is_equal_approx(VoxBoat.DECK, 0.001)
		# Room for a squad and its gear: at least a few metres by more than a metre.
		assert_float(area.size.z).is_greater(2.5)
		assert_float(area.size.x).is_greater(1.2)
		var boxes := VoxBoat.collision(values)
		var console := VoxBoat.console_box(float(VoxBoat.new().with_defaults(values)["length"]))
		for fx: float in [-0.4, 0.0, 0.4]:
			for fz: float in [0.1, 0.3, 0.6, 0.9]:
				var x := area.position.x + area.size.x * (0.5 + fx)
				var z := area.position.z + area.size.z * fz
				if console.grow(0.05).has_point(Vector3(x, console.position.y + 0.1, z)):
					continue
				assert_float(_ground(boxes, x, z)).override_failure_message("%s: floor at %s, %s" % [values, x, z]).is_equal_approx(VoxBoat.DECK, 0.001)
				# Standing height clear over the floor.
				assert_bool(_inside(boxes, Vector3(x, VoxBoat.DECK + 1.0, z))).is_false()
		# The sides stand above the floor all round the well.
		var p := VoxBoat.new().with_defaults(values)
		var l: float = p["length"]
		var mid := area.get_center().z
		var side := VoxBoat.half_width(float(p["beam"]), (mid + l / 2.0) / l) - 0.03
		assert_float(_ground(boxes, side, mid)).is_greater(VoxBoat.DECK + 0.4)


func test_the_warehouse_takes_its_size_from_its_values() -> void:
	var small := VoxWarehouse.footprint({"width": 24.0, "depth": 20.0, "car_park": 0.0})
	var big := VoxWarehouse.footprint({"width": 60.0, "depth": 44.0, "car_park": 20.0})
	assert_float(small.size.x).is_equal_approx(24.0, 0.001)
	assert_float(big.size.x).is_equal_approx(60.0, 0.001)
	assert_float(big.size.z - small.size.z).is_equal_approx(24.0 + 20.0, 0.001)
	# The docks fit along the back however many are asked for.
	assert_int(VoxWarehouse.dock_count({"width": 24.0, "docks": 6.0})).is_less(6)
	assert_int(VoxWarehouse.dock_count({"width": 64.0, "docks": 6.0})).is_equal(6)
	# The sign fits on the front.
	for w: float in [24.0, 64.0]:
		var sign := VoxWarehouse.sign_box({"width": w})
		assert_float(sign.size.x).is_less(w)


func test_the_warehouse_entrance_and_open_dock_lead_inside() -> void:
	var values := {}
	var boxes := VoxWarehouse.collision(values)
	var p := VoxWarehouse.new().with_defaults(values)
	var d: float = p["depth"]
	var floor_y := VoxWarehouse.floor_top(p)
	# Through the front door at head height.
	assert_bool(_inside(boxes, Vector3(0.0, floor_y + 1.5, -d / 2.0 + VoxWarehouse.WALL_THICK * 0.5))).is_false()
	# Through the open shutter, from the dock outside to the one inside.
	var dock := VoxWarehouse.snap(VoxWarehouse.DOCK_HEIGHT, float(p["voxel"]))
	var x := VoxWarehouse.dock_xs(p)[0]
	assert_bool(_inside(boxes, Vector3(x, dock + 1.5, d / 2.0 - VoxWarehouse.WALL_THICK * 0.5))).is_false()
	assert_float(_ground(boxes, x, d / 2.0 + 1.0, dock + 1.0)).is_equal_approx(dock, 0.001)
	assert_float(_ground(boxes, x, d / 2.0 - 1.5, dock + 1.0)).is_equal_approx(dock, 0.001)
	# The other shutters are shut.
	var shut := VoxWarehouse.dock_xs(p)[1]
	assert_bool(_inside(boxes, Vector3(shut, dock + 1.5, d / 2.0 - VoxWarehouse.WALL_THICK * 0.5))).is_true()


func test_the_boat_shed_doorway_is_open_unless_shut() -> void:
	var p := {"depth": 6.0}
	var front := Vector3(0.0, 1.0, 3.0 - VoxBoatShed.WALL_THICK * 0.5)
	assert_bool(_inside(VoxBoatShed.collision(p), front)).is_false()
	p["doors"] = 1.0
	assert_bool(_inside(VoxBoatShed.collision(p), front)).is_true()
	var wide := VoxBoatShed.new().build({"width": 6.0}).cells().x
	var narrow := VoxBoatShed.new().build({"width": 3.0}).cells().x
	assert_int(wide).is_greater(narrow)


func test_flat_packs_stack_and_shelves_carry_them() -> void:
	var one := VoxFlatPack.collision({"count": 1.0})[0]
	var five := VoxFlatPack.collision({"count": 5.0})[0]
	assert_float(five.size.y).is_equal_approx(one.size.y * 5.0, 0.001)
	var empty := VoxShelving.new().build({"fill": 0.0}).voxel_count()
	var full := VoxShelving.new().build({"fill": 1.0}).voxel_count()
	assert_int(full).is_greater(empty)
	# Deck boxes, one a level, plus a frame at each end of every bay.
	assert_int(VoxShelving.collision({"bays": 3.0, "levels": 4.0}).size()).is_equal(4 + 4)

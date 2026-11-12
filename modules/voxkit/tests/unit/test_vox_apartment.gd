extends GdUnitTestSuite
## The apartment block: its parameters change the building they say they do, the stairs
## climb every storey with room to walk, and every stairwell has a way in from the street.

var _gen := VoxApartment.new()


## Filled voxels whose centres are inside the box.
func _solid(model: VoxelModel, box: AABB) -> int:
	var copy: Dictionary = model.copy_box(box.position, box.end)
	return (copy["model"] as VoxelModel).voxel_count()


func test_more_floors_make_a_taller_block() -> void:
	var low := _gen.build({"floors": 2.0})
	var high := _gen.build({"floors": 6.0})
	assert_int(high.cells().y).is_greater(low.cells().y + int(4 * VoxApartment.STOREY / 0.15) - 2)


func test_each_stairwell_is_a_section_with_a_flat_either_side() -> void:
	for n in [1, 2, 4]:
		var plan := _gen.layout({"stairwells": float(n)})
		assert_int((plan["bays"] as Array).size()).is_equal(n)
		assert_int((plan["doors"] as Array).size()).is_equal(n)
		assert_int((plan["flats"] as Array).size()).is_equal(n * 2)


func test_elevators_go_to_stairwells_and_never_outnumber_them() -> void:
	assert_int((_gen.layout({"elevators": 0.0})["elevators"] as Array).size()).is_equal(0)
	assert_int((_gen.layout({"stairwells": 3.0, "elevators": 2.0})["elevators"] as Array).size()).is_equal(2)
	assert_int((_gen.layout({"stairwells": 1.0, "elevators": 4.0})["elevators"] as Array).size()).is_equal(1)
	var plan := _gen.layout({"stairwells": 3.0, "elevators": 1.0})
	var tower: AABB = (plan["elevators"] as Array)[0]
	var middle: Vector2 = (plan["bays"] as Array)[1]
	assert_float(tower.get_center().x).is_equal_approx((middle.x + middle.y) / 2.0, 0.01)
	var model := _gen.build({"stairwells": 3.0, "elevators": 1.0})
	assert_int(_solid(model, tower.grow(-0.3))).is_greater(0)


func test_stairs_climb_from_each_floor_to_the_next() -> void:
	var plan := _gen.layout({"floors": 4.0, "stairwells": 1.0})
	var levels: Array = plan["levels"]
	var steps: Array = plan["steps"]
	var per_storey := VoxApartment.STEPS_PER_FLIGHT * 2
	assert_int(steps.size()).is_equal(per_storey * (levels.size() - 1))
	for i in levels.size() - 1:
		var flight := steps.slice(i * per_storey, (i + 1) * per_storey)
		var last := float(levels[i])
		for step: AABB in flight:
			var rise := step.end.y - last
			assert_float(rise).override_failure_message("storey %d has a step of %.2f m" % [i, rise]).is_between(0.1, 0.2)
			last = step.end.y
		assert_float(last).is_equal_approx(float(levels[i + 1]), 0.001)


func test_every_step_is_built_with_head_room_above_it() -> void:
	var p := {"floors": 3.0, "stairwells": 1.0, "elevators": 0.0, "roof": 2.0}
	var model := _gen.build(p)
	var v: float = _gen.layout(p)["voxel"]
	for step: AABB in _gen.layout(p)["steps"]:
		assert_int(_solid(model, step)).override_failure_message("step at %s is missing" % step.position).is_greater(0)
		# Room for a person above the tread (cell centres from a voxel above it), away from
		# the walls either side.
		var above := AABB(Vector3(step.position.x + v, step.end.y + v, step.position.z), Vector3(step.size.x - v * 2.0, _headroom(), step.size.z))
		assert_int(_solid(model, above)).override_failure_message("something blocks the stairs above %s" % step.position).is_equal(0)


func test_the_front_door_leads_into_the_stairwell() -> void:
	var p := {"stairwells": 2.0, "basement": 1.0}
	var model := _gen.build(p)
	var plan := _gen.layout(p)
	var wall: float = plan["wall"]
	for door: Vector3 in plan["doors"]:
		# Just inside the door: the stairwell floor is there and the hall above it is open.
		var hall := AABB(Vector3(door.x - 0.4, float(plan["ground"]) + 0.2, door.z + wall + 0.2), Vector3(0.8, 1.8, 0.6))
		assert_int(_solid(model, hall)).is_equal(0)
		var floor := AABB(Vector3(door.x - 0.4, float(plan["ground"]) - 0.2, door.z + wall + 0.2), Vector3(0.8, 0.15, 0.6))
		assert_int(_solid(model, floor)).is_greater(0)
	# On every landing a doorway through each side wall into a flat.
	var zf := -float(plan["depth"]) / 2.0 + wall
	for level: float in plan["levels"]:
		for bay: Vector2 in plan["bays"]:
			for side: float in [bay.x, bay.y]:
				var way := AABB(Vector3(side - wall, level + 0.1, zf + 0.35), Vector3(wall * 2.0, 1.8, 0.6))
				assert_int(_solid(model, way)).override_failure_message("no way into the flat at x %.1f, level %.1f" % [side, level]).is_equal(0)


func test_balconies_hang_off_the_courtyard_side_only_when_asked() -> void:
	var base := {"elevators": 0.0, "stairwells": 1.0}
	var plan := _gen.layout(base)
	var d: float = plan["depth"]
	# In front of the first flat, clear of the stairwell's steps and canopy, and beyond the
	# window sills and the eaves.
	var flat: Vector2 = (plan["flats"] as Array)[0]
	var outside := AABB(Vector3(flat.x, 0.5, d / 2.0 + 0.6), Vector3(flat.y - flat.x, 20.0, 0.7))
	var street := AABB(Vector3(flat.x, 0.5, -d / 2.0 - 1.3), Vector3(flat.y - flat.x, 20.0, 0.7))
	var none := base.merged({"balconies": 0.0})
	var back := base.merged({"balconies": 1.0, "balcony_sides": 0.0})
	var both := base.merged({"balconies": 1.0, "balcony_sides": 1.0})
	assert_int(_solid(_gen.build(none), outside)).is_equal(0)
	assert_int(_solid(_gen.build(back), outside)).is_greater(0)
	assert_int(_solid(_gen.build(back), street)).is_equal(0)
	assert_int(_solid(_gen.build(both), street)).is_greater(0)


func test_a_huge_block_coarsens_its_voxels_instead_of_being_clipped() -> void:
	var p := {"floors": 8.0, "stairwells": 4.0, "flat_width": 7.5, "depth": 13.0, "voxel": 0.1}
	var plan := _gen.layout(p)
	assert_float(float(plan["voxel"])).is_greater(0.1)
	var model := _gen.build(p)
	var cells := model.cells()
	var v := model.voxel_size()
	assert_float(cells.x * v).is_greater(float(plan["length"]))
	assert_float(cells.y * v).is_greater(float(plan["eaves"]))


func _kinds(flat_plan: Dictionary) -> Array:
	return (flat_plan["rooms"] as Array).map(func(r: Dictionary) -> String: return r["kind"])


func test_every_flat_has_a_kitchen_a_bathroom_a_hall_and_a_living_room() -> void:
	for windows in [1.0, 2.0, 3.0]:
		var plan := _gen.layout({"stairwells": 4.0, "windows": windows})
		for fp: Dictionary in plan["flat_plans"]:
			for kind in ["kitchen", "living", "bath", "hall"]:
				assert_bool(kind in _kinds(fp)).override_failure_message("a %d-window flat has no %s" % [windows, kind]).is_true()


func test_one_window_flats_are_studios_and_bigger_flats_come_in_different_sizes() -> void:
	for fp: Dictionary in _gen.layout({"windows": 1.0})["flat_plans"]:
		assert_int(int(fp["bedrooms"])).is_equal(0)
	for seed in 6:
		for fp: Dictionary in _gen.layout({"stairwells": 4.0, "windows": 2.0, "seed": float(seed)})["flat_plans"]:
			assert_int(int(fp["bedrooms"])).is_greater(0)
			assert_int(_kinds(fp).count("bedroom")).is_equal(int(fp["bedrooms"]))
	# Flats in the same block come in different sizes, some with several bedrooms.
	for p: Dictionary in [{"windows": 2.0}, {"windows": 3.0, "flat_width": 7.5}]:
		var sizes := {}
		for seed in 6:
			for fp: Dictionary in _gen.layout(p.merged({"stairwells": 4.0, "seed": float(seed)}))["flat_plans"]:
				sizes[int(fp["bedrooms"])] = true
		assert_int(sizes.size()).override_failure_message("every flat the same size with %s" % p).is_greater_equal(2)
		assert_int(sizes.keys().max()).is_greater_equal(2)


func test_no_room_is_too_narrow_to_move_in() -> void:
	for width in [4.5, 6.0, 7.5]:
		for windows in [1.0, 2.0, 3.0]:
			for seed in 4:
				var plan := _gen.layout({"stairwells": 2.0, "flat_width": width, "windows": windows, "seed": float(seed)})
				for fp: Dictionary in plan["flat_plans"]:
					for room: Dictionary in fp["rooms"]:
						var r: Rect2 = room["rect"]
						if room["kind"] == "hall":
							continue
						var narrow := minf(r.size.x, r.size.y)
						var least := ApartmentRooms.MIN_ROOM - 0.01
						if room["kind"] == "bath":
							least = ApartmentRooms.HALL - 0.01
						elif room["kind"] == "living":
							least = minf(ApartmentRooms.MIN_LIVING, width - 0.6) - 0.01
						assert_float(narrow).override_failure_message("a %s %.2f m across (%.1f m flat, %d windows)" % [room["kind"], narrow, width, windows]).is_greater(least)


func test_rooms_stay_inside_their_flat_and_never_overlap() -> void:
	var plan := _gen.layout({"stairwells": 2.0, "windows": 3.0, "seed": 4.0})
	var flats: Array = plan["flats"]
	for f in flats.size():
		var inner := VoxApartment.inner_rect(plan, flats[f])
		var rooms: Array = plan["flat_plans"][f]["rooms"]
		for i in rooms.size():
			var a: Rect2 = rooms[i]["rect"]
			assert_bool(inner.grow(0.01).encloses(a)).override_failure_message("%s pokes out of its flat" % rooms[i]["kind"]).is_true()
			for j in range(i + 1, rooms.size()):
				assert_bool(a.grow(-0.01).intersects(rooms[j]["rect"])).override_failure_message("%s overlaps %s" % [rooms[i]["kind"], rooms[j]["kind"]]).is_false()


## Empty from just above the floor to head height over `r`, shrunk by a voxel each side.
func _clear(model: VoxelModel, r: Rect2, level: float, v: float) -> int:
	var inner := r.grow(-v)
	return _solid(model, AABB(Vector3(inner.position.x, level + 0.01, inner.position.y), Vector3(inner.size.x, 1.9, inner.size.y)))


func test_furniture_never_blocks_a_doorway_or_the_way_in() -> void:
	for seed in [1.0, 3.0, 8.0]:
		var p := {"stairwells": 2.0, "windows": 3.0, "floors": 2.0, "elevators": 0.0, "seed": seed}
		var model := _gen.build(p)
		var plan := _gen.layout(p)
		var v: float = plan["voxel"]
		for level: float in plan["levels"]:
			for fp: Dictionary in plan["flat_plans"]:
				assert_int(_clear(model, fp["entry"], level, v)).override_failure_message("the way in is blocked (seed %d)" % seed).is_equal(0)
				for door: Dictionary in fp["doors"]:
					var r: Rect2 = door["rect"]
					assert_int(_clear(model, r.grow(v), level, v)).override_failure_message("a doorway is blocked at %s" % r).is_equal(0)
					# Room to step through: 0.6 m either side of the opening.
					var sides: Array[Rect2] = []
					if int(door["across"]) == 1:
						sides = [Rect2(r.position.x, r.position.y - 0.6, r.size.x, 0.6 + v), Rect2(r.position.x, r.end.y - v, r.size.x, 0.6 + v)]
					else:
						sides = [Rect2(r.position.x - 0.4, r.position.y, 0.4 + v, r.size.y), Rect2(r.end.x - v, r.position.y, 0.4 + v, r.size.y)]
					for s in sides:
						assert_int(_clear(model, s.grow(v), level, v)).override_failure_message("furniture in front of the door at %s (seed %d)" % [r, seed]).is_equal(0)


func test_rooms_and_furniture_are_options() -> void:
	var p := {"stairwells": 1.0, "floors": 2.0, "elevators": 0.0}
	var empty := _gen.build(p.merged({"interior": 0.0})).voxel_count()
	var rooms := _gen.build(p.merged({"interior": 1.0})).voxel_count()
	var furnished := _gen.build(p.merged({"interior": 2.0})).voxel_count()
	assert_int(rooms).is_greater(empty)
	assert_int(furnished).is_greater(rooms)


func test_every_room_opens_onto_the_hall() -> void:
	for seed in 8:
		for windows in [1.0, 2.0, 3.0]:
			var plan := _gen.layout({"stairwells": 2.0, "windows": windows, "seed": float(seed)})
			for fp: Dictionary in plan["flat_plans"]:
				var rooms: Array = fp["rooms"]
				var hall: Rect2 = rooms.filter(func(r: Dictionary) -> bool: return r["kind"] == "hall")[0]["rect"]
				for room: Dictionary in rooms:
					if room["kind"] == "hall":
						continue
					var way_in := false
					for door: Dictionary in fp["doors"]:
						var d: Rect2 = (door["rect"] as Rect2).grow(0.05)
						if d.intersects(room["rect"]) and d.intersects(hall):
							way_in = true
					assert_bool(way_in).override_failure_message("a %s has no door onto the hall (seed %d, %d windows)" % [room["kind"], seed, windows]).is_true()


## The player's body from its own module's data, or empty when that module is gone.
func _player() -> Dictionary:
	var path := "res://modules/player/data/player.json"
	if not FileAccess.file_exists(path):
		return {}
	return Data.load_json(path)


func test_everything_is_sized_for_the_player() -> void:
	var body := _player()
	if body.is_empty():
		return
	var tall: float = body["stand_height"]
	var wide := float(body["radius"]) * 2.0
	var jump := pow(float(body["jump_velocity"]), 2.0) / (2.0 * 9.8)
	var eye := tall - float(body["eye_offset"])
	# Room to jump under every ceiling.
	assert_float(VoxApartment.STOREY - VoxApartment.SLAB).is_greater(tall + jump)
	# Every opening fits a person with room either side and over their head.
	var openings := {
		"front door": VoxApartment.DOOR, "flat door": VoxApartment.FLAT_DOOR,
		"room door": ApartmentRooms.DOOR, "bathroom door": Vector2(ApartmentRooms.BATH_DOOR, ApartmentRooms.DOOR.y),
	}
	for name: String in openings:
		var size: Vector2 = openings[name]
		assert_float(size.x).override_failure_message("the %s is %.2f m wide" % [name, size.x]).is_greater_equal(wide + 0.15)
		assert_float(size.y).override_failure_message("the %s is %.2f m high" % [name, size.y]).is_greater_equal(tall + 0.1)
	# Halls, stair flights and rooms leave room to pass and turn.
	assert_float(ApartmentRooms.HALL).is_greater_equal(wide + 0.3)
	var plan := _gen.layout({})
	var bay: Vector2 = (plan["bays"] as Array)[0]
	var flight := (bay.y - bay.x - float(plan["wall"])) / 2.0
	assert_float(flight).is_greater_equal(wide + 0.3)
	assert_float(ApartmentRooms.MIN_ROOM).is_greater_equal(wide * 3.0)
	# Standing at a window you can see out of it: the sill below the eyes, the top above.
	assert_float(VoxApartment.WINDOW_SILL).is_less(eye - 0.3)
	assert_float(VoxApartment.WINDOW_SILL + VoxApartment.WINDOW.y).is_greater(eye + 0.2)
	# Balcony railings come to about the hip.
	assert_float(VoxApartment.RAIL_HEIGHT).is_between(tall * 0.5, tall * 0.65)


## Head room to keep clear over a tread: the player's height and a little, or 1.9 m.
func _headroom() -> float:
	var body := _player()
	return 1.9 if body.is_empty() else float(body["stand_height"]) + 0.1

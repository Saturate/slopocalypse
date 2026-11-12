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
		var above := AABB(Vector3(step.position.x + v, step.end.y + v, step.position.z), Vector3(step.size.x - v * 2.0, 1.9, step.size.z))
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

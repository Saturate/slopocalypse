extends GdUnitTestSuite

const SOURCES: Array[StringName] = [&"building", &"building_chip", &"crater", &"tree", &"tree_cut", &"tree_blast", &"tree_crown"]

var _parent: Node3D


func before_test() -> void:
	_parent = auto_free(Node3D.new())
	add_child(_parent)


func _cfg(speed_jitter: float, angle_jitter: float, spin_max: float) -> Dictionary:
	return {"count": 30.0, "speed": 5.0, "speed_jitter": speed_jitter, "angle_jitter_degrees": angle_jitter, "spin_max": spin_max, "lifetime_seconds": 1.6}


func _debris(cfg: Dictionary, towards: Vector3, seed_value: int) -> VoxelDebris:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var d: VoxelDebris = auto_free(VoxelDebris.new())
	d.setup(towards, Color.WHITE, cfg, int(cfg["count"]), float(cfg["speed"]), rng)
	return d


func test_every_source_has_a_complete_entry() -> void:
	for source in SOURCES:
		assert_bool(VoxelDebris.config(source).is_empty()).override_failure_message(String(source)).is_false()


func test_two_bursts_at_the_same_point_differ() -> void:
	var a := VoxelDebris.burst(_parent, Vector3.ZERO, Vector3.UP, Color.WHITE, &"building")
	var b := VoxelDebris.burst(_parent, Vector3.ZERO, Vector3.UP, Color.WHITE, &"building")
	assert_int(a.velocities.size()).is_equal(b.velocities.size())
	var same := 0
	for i in a.velocities.size():
		if a.velocities[i].is_equal_approx(b.velocities[i]):
			same += 1
	assert_int(same).is_less(a.velocities.size())


func test_pieces_stay_within_the_jitter() -> void:
	var cfg := _cfg(0.3, 20.0, 8.0)
	var towards := Vector3(1.0, 1.0, 0.0).normalized()
	for seed_value in 20:
		var d := _debris(cfg, towards, seed_value)
		for i in d.velocities.size():
			var v := d.velocities[i]
			assert_float(v.length()).is_between(5.0 * 0.7 - 0.001, 5.0 * 1.3 + 0.001)
			assert_float(rad_to_deg(v.angle_to(towards))).is_less_equal(20.0 + 0.01)
			var w := d.spins[i]
			for axis in 3:
				assert_float(absf(w[axis])).is_less_equal(8.0)


func test_tilt_goes_every_way_round() -> void:
	var d := _debris(_cfg(0.0, 20.0, 0.0), Vector3.UP, 7)
	var east := 0
	var west := 0
	for v in d.velocities:
		if v.x > 0.0:
			east += 1
		elif v.x < 0.0:
			west += 1
	assert_int(east).is_greater(0)
	assert_int(west).is_greater(0)


func test_no_jitter_throws_every_piece_straight_at_full_speed() -> void:
	var towards := Vector3(0.0, 1.0, -1.0).normalized()
	var d := _debris(_cfg(0.0, 0.0, 0.0), towards, 3)
	for i in d.velocities.size():
		assert_bool(d.velocities[i].is_equal_approx(towards * 5.0)).is_true()
		assert_bool(d.spins[i].is_zero_approx()).is_true()


func test_burst_frees_itself_after_its_lifetime() -> void:
	var d := VoxelDebris.burst(_parent, Vector3.ZERO, Vector3.UP, Color.WHITE, &"tree")
	d._process(float(VoxelDebris.config(&"tree")["lifetime_seconds"]) + 0.1)
	await get_tree().process_frame
	assert_bool(is_instance_valid(d)).is_false()


func test_past_the_cap_the_oldest_go_and_the_count_never_exceeds_it() -> void:
	VoxelDebris.config(&"building")
	var cap := VoxelDebris.max_pieces()
	assert_int(cap).is_greater(0)
	var per := int(VoxelDebris.config(&"building")["count"])
	var bursts: Array[VoxelDebris] = []
	var before := VoxelDebris.live_count()
	for i in ceili(float(cap) / per) + 3:
		bursts.append(VoxelDebris.burst(_parent, Vector3.ZERO, Vector3.UP, Color.WHITE, &"building"))
		assert_int(VoxelDebris.live_count()).is_less_equal(cap)
	assert_int(VoxelDebris.live_count()).is_equal(cap)
	# The first bursts went (or lost cubes); the newest is whole.
	assert_bool(bursts[0].pieces() == 0 or bursts[0].is_queued_for_deletion()).is_true()
	assert_int(bursts[-1].pieces()).is_equal(per)
	assert_int(before).is_less_equal(cap)

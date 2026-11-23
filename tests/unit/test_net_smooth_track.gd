extends GdUnitTestSuite
## A client shows a remote thing a little in the past, blended between the server updates
## either side of that moment, so uneven packets and fast screens don't make it jump.


func _track() -> NetSmoothTrack:
	var t := NetSmoothTrack.new()
	t.delay = 0.1
	t.extrapolate = 0.1
	t.snap_distance = 5.0
	t.kinds = [NetSmoothTrack.LINEAR, NetSmoothTrack.ANGLE]
	t.snap_index = 0
	return t


func test_it_shows_the_moment_delay_ago_blended_between_updates() -> void:
	var t := _track()
	t.push(1.0, [Vector3(0, 0, 0), 0.0])
	t.push(1.1, [Vector3(1, 0, 0), 0.2])
	t.push(1.2, [Vector3(2, 0, 0), 0.4])
	# Before the first update it waits on the first.
	assert_vector(t.sample(0.9)[0]).is_equal(Vector3.ZERO)
	# 1.25 - 0.1 = 1.15: half way between the second and third.
	var now := t.sample(1.25)
	assert_vector(now[0]).is_equal_approx(Vector3(1.5, 0, 0), Vector3.ONE * 0.0001)
	assert_float(now[1]).is_equal_approx(0.3, 0.0001)


func test_angles_blend_the_short_way_round() -> void:
	var t := _track()
	t.push(1.0, [Vector3.ZERO, deg_to_rad(170.0)])
	t.push(1.1, [Vector3.ZERO, deg_to_rad(-170.0)])
	var yaw: float = t.sample(1.15)[1]
	# Through 180, not back through 0.
	assert_float(absf(angle_difference(yaw, PI))).is_less(0.0001)


func test_vector_angles_blend_each_axis_the_short_way() -> void:
	var t := NetSmoothTrack.new()
	t.delay = 0.0
	t.kinds = [NetSmoothTrack.ANGLE]
	t.push(1.0, [Vector3(0.0, deg_to_rad(170.0), 0.2)])
	t.push(2.0, [Vector3(0.4, deg_to_rad(-170.0), 0.0)])
	var r: Vector3 = t.sample(1.5)[0]
	assert_float(r.x).is_equal_approx(0.2, 0.0001)
	assert_float(absf(angle_difference(r.y, PI))).is_less(0.0001)
	assert_float(r.z).is_equal_approx(0.1, 0.0001)


func test_it_carries_on_briefly_when_updates_stop_then_holds() -> void:
	var t := _track()
	t.push(1.0, [Vector3(0, 0, 0), 0.0])
	t.push(1.1, [Vector3(1, 0, 0), 0.1])
	# 0.05 s past the newest: keeps going at 10 m/s.
	assert_vector(t.sample(1.25)[0]).is_equal_approx(Vector3(1.5, 0, 0), Vector3.ONE * 0.0001)
	# Long past it: no further than `extrapolate` allows.
	assert_vector(t.sample(3.0)[0]).is_equal_approx(Vector3(2.0, 0, 0), Vector3.ONE * 0.0001)
	assert_float(t.sample(3.0)[1]).is_equal_approx(0.2, 0.0001)


func test_a_teleport_shows_at_once() -> void:
	var t := _track()
	t.push(1.0, [Vector3(0, 0, 0), 0.0])
	t.push(1.1, [Vector3(1, 0, 0), 0.0])
	t.push(1.2, [Vector3(100, 0, 0), 1.0])
	assert_vector(t.sample(1.2)[0]).is_equal(Vector3(100, 0, 0))
	assert_float(t.sample(1.2)[1]).is_equal(1.0)


func test_two_updates_in_one_frame_keep_the_newer() -> void:
	var t := _track()
	t.push(1.0, [Vector3(0, 0, 0), 0.0])
	t.push(1.1, [Vector3(1, 0, 0), 0.0])
	t.push(1.1, [Vector3(2, 0, 0), 0.0])
	assert_vector(t.sample(1.2)[0]).is_equal_approx(Vector3(2, 0, 0), Vector3.ONE * 0.0001)
	assert_vector(t.sample(1.15)[0]).is_equal_approx(Vector3(1, 0, 0), Vector3.ONE * 0.0001)


func test_it_keeps_only_what_it_still_needs() -> void:
	var t := _track()
	for i in 100:
		t.push(float(i) * 0.016, [Vector3(i, 0, 0), 0.0])
		t.sample(float(i) * 0.016)
	assert_int(t.size()).is_less(12)


func test_standing_still_then_moving_blends_from_where_it_stood() -> void:
	var t := _track()
	t.push(1.0, [Vector3(1, 0, 0), 0.2])
	t.push(1.1, [Vector3(1, 0, 0), 0.2])
	t.push(1.2, [Vector3(3, 0, 0), 0.4])
	# 1.15 - 0.1 = 1.05: between two equal updates, it stands.
	var still := t.sample(1.15)
	assert_vector(still[0]).is_equal(Vector3(1, 0, 0))
	assert_float(still[1]).is_equal_approx(0.2, 0.0001)
	# 1.25 - 0.1 = 1.15: half way from where it stood to where it went.
	var moving := t.sample(1.25)
	assert_vector(moving[0]).is_equal_approx(Vector3(2, 0, 0), Vector3.ONE * 0.0001)
	assert_float(moving[1]).is_equal_approx(0.3, 0.0001)
	# The still sample is not changed by sampling again later.
	assert_vector(still[0]).is_equal(Vector3(1, 0, 0))

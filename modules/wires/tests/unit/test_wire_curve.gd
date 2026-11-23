extends GdUnitTestSuite
## A wire's sag curve and barbs: it starts and ends exactly on the attach points, hangs as far as its
## sag says, is symmetric on a level span, dips toward the lower end between different
## heights, and gets fewer segments far from the camera.

const EPS := Vector3.ONE * 0.0001


func test_the_ends_are_exactly_the_attach_points() -> void:
	var a := Vector3(3.25, 11.5, -7.125)
	var b := Vector3(181.75, 4.0, 92.5)
	var line := WireCurve.points(a, b, 6.0, 17)
	assert_int(line.size()).is_equal(18)
	assert_bool(line[0] == a).is_true()
	assert_bool(line[line.size() - 1] == b).is_true()


func test_a_level_span_hangs_its_sag_at_the_middle() -> void:
	var a := Vector3(0, 10, 0)
	var b := Vector3(100, 10, 0)
	var sag := WireCurve.sag_for(a, b, 0.04)
	assert_float(sag).is_equal_approx(4.0, 0.0001)
	var low := WireCurve.lowest_point(a, b, sag)
	assert_vector(low).is_equal_approx(Vector3(50, 6, 0), EPS)
	# No point of the drawn curve hangs below it.
	for p in WireCurve.points(a, b, sag, 40):
		assert_float(p.y).is_greater_equal(low.y - 0.0001)


func test_a_level_span_is_symmetric() -> void:
	var a := Vector3(-20, 5, 4)
	var b := Vector3(20, 5, -4)
	var line := WireCurve.points(a, b, 1.5, 10)
	var mid := (a + b) * 0.5
	for i in line.size():
		var mirror := line[line.size() - 1 - i]
		assert_float(line[i].y).is_equal_approx(mirror.y, 0.0001)
		# Across the ground the two are reflections through the middle.
		assert_vector(line[i] - mid).is_equal_approx(Vector3(mid.x - mirror.x, line[i].y - mid.y, mid.z - mirror.z), EPS)


func test_between_different_heights_it_dips_toward_the_lower_end() -> void:
	var low_end := Vector3(0, 10, 0)
	var high_end := Vector3(60, 14, 0)
	var sag := 3.0
	var t := WireCurve.lowest_t(low_end, high_end, sag)
	# Slope of height along t is rise - 4·sag·(1 - 2t): zero at 0.5 - 4 / 24.
	assert_float(t).is_equal_approx(0.5 - 4.0 / 24.0, 0.0001)
	var lowest := WireCurve.lowest_point(low_end, high_end, sag)
	assert_float(lowest.y).is_less(low_end.y)
	for p in WireCurve.points(low_end, high_end, sag, 60):
		assert_float(p.y).is_greater_equal(lowest.y - 0.0001)
	# The same span hung the other way round has its lowest point the same distance from
	# the lower end.
	var back := WireCurve.lowest_point(high_end, low_end, sag)
	assert_vector(back).is_equal_approx(lowest, EPS)


func test_a_steep_span_is_lowest_at_its_lower_end() -> void:
	var a := Vector3(0, 0, 0)
	var b := Vector3(10, 20, 0)
	assert_float(WireCurve.lowest_t(a, b, 0.5)).is_equal(0.0)
	assert_vector(WireCurve.lowest_point(a, b, 0.5)).is_equal(a)
	assert_float(WireCurve.lowest_t(b, a, 0.5)).is_equal(1.0)


func test_a_stretch_of_the_span_lies_on_the_whole_curve() -> void:
	var a := Vector3(0, 30, 0)
	var b := Vector3(240, 26, 30)
	var whole := WireCurve.points(a, b, 8.0, 8)
	var part := WireCurve.points_between(a, b, 8.0, 0.25, 0.5, 2)
	assert_vector(part[0]).is_equal_approx(whole[2], EPS)
	assert_vector(part[1]).is_equal_approx(whole[3], EPS)
	assert_vector(part[2]).is_equal_approx(whole[4], EPS)


func test_segments_follow_length_and_distance() -> void:
	var steps := [{"until": 70.0, "detail": 1.0}, {"until": 220.0, "detail": 0.35}, {"until": 900.0, "detail": 0.12}]
	assert_int(WireCurve.segment_count(30.0, 1.0)).is_equal(30)
	assert_int(WireCurve.segment_count(30.5, 1.0)).is_equal(31)
	assert_int(WireCurve.segment_count(0.2, 1.0, 2)).is_equal(2)
	assert_int(WireCurve.step_at(10.0, steps)).is_equal(0)
	assert_int(WireCurve.step_at(70.0, steps)).is_equal(1)
	assert_int(WireCurve.step_at(5000.0, steps)).is_equal(2)
	var near := WireCurve.segments_at(60.0, 1.0, 0.0, steps)
	var mid := WireCurve.segments_at(60.0, 1.0, 100.0, steps)
	var far := WireCurve.segments_at(60.0, 1.0, 400.0, steps)
	assert_int(near).is_equal(60)
	assert_int(mid).is_equal(21)
	assert_int(far).is_equal(8)
	# A short span still bends.
	assert_int(WireCurve.segments_at(3.0, 1.0, 400.0, steps)).is_equal(2)


func test_barbs_are_neither_doubled_nor_dropped_where_a_span_is_cut() -> void:
	for case: Array in [[100.0, 0.25, 4], [97.3, 0.25, 3], [33.1, 0.3, 2], [64.0, 0.25, 7]]:
		var span: float = case[0]
		var spacing: float = case[1]
		var pieces: int = case[2]
		var whole := WireMesh.barb_ts(span, spacing, 0.0, 1.0)
		var joined := PackedFloat32Array()
		for i in pieces:
			joined.append_array(WireMesh.barb_ts(span, spacing, float(i) / float(pieces), float(i + 1) / float(pieces)))
		assert_int(joined.size()).is_equal(whole.size())
		assert_array(Array(joined)).is_equal(Array(whole))
		assert_int(whole.size()).is_equal(floori(span / spacing - 0.5) + 1)

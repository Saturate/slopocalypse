extends GdUnitTestSuite
## The geometry MapPower routes with (#494): whether a span passes over a footprint, the
## spots tried round a settlement, and a pole's place beside a road.


func test_a_span_meets_a_rect_it_crosses_and_misses_one_beside_it() -> void:
	var rect := Rect2(0, 0, 10, 10)
	assert_bool(MapPower.segment_meets(rect, Vector2(-5, 5), Vector2(15, 5))).is_true()
	assert_bool(MapPower.segment_meets(rect, Vector2(-5, -5), Vector2(15, 15))).is_true()
	assert_bool(MapPower.segment_meets(rect, Vector2(2, 2), Vector2(3, 3))).is_true()
	assert_bool(MapPower.segment_meets(rect, Vector2(-5, 12), Vector2(15, 12))).is_false()
	assert_bool(MapPower.segment_meets(rect, Vector2(-5, -1), Vector2(-1, 20))).is_false()
	# Stopping short of it.
	assert_bool(MapPower.segment_meets(rect, Vector2(-20, 5), Vector2(-1, 5))).is_false()


func test_the_ring_round_a_settlement_starts_nearest_the_way_out() -> void:
	var spots := MapPower._ring(Rect2(-50, -50, 100, 100), Vector2(500, 0))
	assert_int(spots.size()).is_greater(40)
	assert_vector(spots[0]).is_equal_approx(Vector2(50, 0), Vector2(MapPower.RING_STEP, MapPower.RING_STEP))
	for p in spots:
		var on_edge := is_equal_approx(absf(p.x), 50.0) or is_equal_approx(absf(p.y), 50.0)
		assert_bool(on_edge).override_failure_message("%s is not on the edge" % p).is_true()


func test_a_pole_spot_is_set_back_from_the_road_edge_on_either_side() -> void:
	var points := PackedVector2Array([Vector2(0, 0), Vector2(100, 0)])
	var halves := PackedFloat32Array([3.5, 3.5])
	var along := PackedFloat32Array([0.0, 100.0])
	var left := MapPower._beside(points, halves, along, 40.0, 4.0)
	var right := MapPower._beside(points, halves, along, 40.0, -4.0)
	assert_float(left.x).is_equal_approx(40.0, 0.001)
	assert_float(absf(left.y)).is_equal_approx(7.5, 0.001)
	assert_float(right.y).is_equal_approx(-left.y, 0.001)

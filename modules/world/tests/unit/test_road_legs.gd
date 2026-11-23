extends GdUnitTestSuite
## A winding track whose legs come back side by side has the loop between them cut out
## (#470), and a wide hairpin is left alone.

const WIDTH := 3.5


func _hairpin(gap: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in 11:
		out.append(Vector2(0.0, k * 4.0))
	for k in range(10, -1, -1):
		out.append(Vector2(gap, k * 4.0))
	return out


func test_legs_closer_than_a_width_are_joined_where_they_meet() -> void:
	var merged := RoadNetwork.merge_legs(_hairpin(2.0), WIDTH)
	assert_int(merged.size()).is_less(_hairpin(2.0).size())
	# Both ends stay where they were.
	assert_vector(merged[0]).is_equal(Vector2.ZERO)
	assert_vector(merged[merged.size() - 1]).is_equal(Vector2(2.0, 0.0))
	# Nothing far along the line comes back within a width of an earlier point.
	for a in merged.size():
		var further := 0.0
		for b in range(a + 1, merged.size()):
			further += merged[b].distance_to(merged[b - 1])
			if further > WIDTH * 3.0:
				assert_float(merged[a].distance_to(merged[b])).is_greater_equal(WIDTH)


func test_a_wide_hairpin_is_kept() -> void:
	assert_int(RoadNetwork.merge_legs(_hairpin(20.0), WIDTH).size()).is_equal(_hairpin(20.0).size())

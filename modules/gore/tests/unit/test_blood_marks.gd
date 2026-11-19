extends GdUnitTestSuite
## Blood marks and pools: at most `max_marks` at once with the oldest going first, a pool
## spreading to its full size over its spread time, and every mark fading out after
## `mark_seconds`.

var _cfg: Dictionary


func before_test() -> void:
	_cfg = BloodEffects.config().duplicate()
	_cfg["max_marks"] = 3.0
	_cfg["mark_seconds"] = 10.0
	_cfg["fade_seconds"] = 2.0
	_cfg["pool_seconds"] = 4.0
	_cfg["pool_start_share"] = 0.25


func _marks() -> BloodMarks:
	var marks: BloodMarks = auto_free(BloodMarks.new())
	marks.setup(_cfg)
	marks.set_process(false)
	add_child(marks)
	return marks


func test_the_oldest_mark_goes_first_past_the_cap() -> void:
	var marks := _marks()
	var first := marks.add_mark(Vector3(0, 0, 0), Vector3.UP, Vector3.FORWARD, 0.5, 0.5)
	marks.add_mark(Vector3(1, 0, 0), Vector3.UP, Vector3.FORWARD, 0.5, 0.5)
	marks.add_mark(Vector3(2, 0, 0), Vector3.UP, Vector3.FORWARD, 0.5, 0.5)
	assert_int(marks.count()).is_equal(3)
	var fourth := marks.add_mark(Vector3(3, 0, 0), Vector3.UP, Vector3.FORWARD, 0.5, 0.5)
	assert_int(marks.count()).is_equal(3)
	assert_bool(is_instance_valid(first) and first.is_inside_tree()).is_false()
	assert_bool(fourth.is_inside_tree()).is_true()


func test_a_mark_lies_on_the_surface_turned_to_it() -> void:
	var marks := _marks()
	var wall_normal := Vector3(0, 0, 1)
	# A shot coming in at a slant smears the mark along the wall.
	var decal := marks.add_mark(Vector3(0, 1, -3), wall_normal, Vector3(1, 0, -1).normalized(), 0.4, 0.8)
	assert_vector(decal.global_transform.basis.y.normalized()).is_equal_approx(wall_normal, Vector3.ONE * 0.001)
	assert_vector(decal.global_position).is_equal_approx(Vector3(0, 1, -3), Vector3.ONE * 0.001)
	assert_float(decal.size.x).is_equal_approx(0.8, 0.001)
	assert_float(decal.size.z).is_equal_approx(0.4, 0.001)
	# Its long side runs along the wall, the way the shot was going.
	assert_float(absf(decal.global_transform.basis.x.normalized().dot(Vector3.RIGHT))).is_greater(0.99)


func test_marks_fade_out_after_their_time() -> void:
	var marks := _marks()
	var decal := marks.add_mark(Vector3.ZERO, Vector3.UP, Vector3.FORWARD, 0.5, 0.5)
	var alpha := decal.modulate.a
	marks.advance(9.0)
	assert_float(decal.modulate.a).is_equal_approx(alpha, 0.001)
	marks.advance(2.0)
	assert_float(decal.modulate.a).is_less(alpha)
	assert_float(decal.modulate.a).is_greater(0.0)
	marks.advance(1.5)
	assert_int(marks.count()).is_equal(0)


func test_a_pool_spreads_to_its_radius_over_its_time() -> void:
	var marks := _marks()
	var pool := marks.add_pool(Vector3.ZERO, Vector3.UP, 0.8)
	assert_float(pool.size.x).is_equal_approx(0.8 * 2.0 * 0.25, 0.001)
	marks.advance(2.0)
	assert_float(pool.size.x).is_greater(0.4)
	assert_float(pool.size.x).is_less(1.6)
	marks.advance(2.5)
	assert_float(pool.size.x).is_equal_approx(1.6, 0.001)
	assert_float(pool.size.z).is_equal_approx(1.6, 0.001)


func test_no_marks_at_all_when_the_cap_is_zero() -> void:
	_cfg["max_marks"] = 0.0
	var marks := _marks()
	assert_object(marks.add_mark(Vector3.ZERO, Vector3.UP, Vector3.FORWARD, 0.5, 0.5)).is_null()
	assert_object(marks.add_pool(Vector3.ZERO, Vector3.UP, 0.8)).is_null()
	assert_int(marks.count()).is_equal(0)


func test_clear_takes_every_mark_away() -> void:
	var marks := _marks()
	marks.add_mark(Vector3.ZERO, Vector3.UP, Vector3.FORWARD, 0.5, 0.5)
	marks.add_pool(Vector3.ONE, Vector3.UP, 0.8)
	marks.clear()
	assert_int(marks.count()).is_equal(0)
	assert_int(marks.get_child_count()).is_equal(0)

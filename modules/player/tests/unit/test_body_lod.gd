extends GdUnitTestSuite
## How often someone else's body is posed: every frame up close and in view, less often
## further off or out of view, and a scope's zoom counts as coming closer.

func _lod() -> BodyLod:
	var lod := BodyLod.new()
	lod.near_distance = 15.0
	lod.far_distance = 40.0
	lod.mid_rate = 30.0
	lod.far_rate = 15.0
	lod.off_screen_rate = 10.0
	lod.reference_fov = 80.0
	return lod


func test_near_and_in_view_is_every_frame() -> void:
	assert_float(_lod().interval(5.0, true)).is_equal(0.0)


func test_further_off_is_posed_less_often() -> void:
	var lod := _lod()
	assert_float(lod.interval(20.0, true)).is_equal_approx(1.0 / 30.0, 0.0001)
	assert_float(lod.interval(60.0, true)).is_equal_approx(1.0 / 15.0, 0.0001)


func test_out_of_view_is_posed_least_often_even_up_close() -> void:
	assert_float(_lod().interval(2.0, false)).is_equal_approx(1.0 / 10.0, 0.0001)


func test_a_zoomed_view_brings_bodies_closer() -> void:
	var lod := _lod()
	assert_float(lod.zoom_for(80.0)).is_equal_approx(1.0, 0.0001)
	# A 4x scope narrows the view to about 23 degrees: 60 m looks like 15 m.
	assert_float(lod.zoom_for(23.0) * 60.0).is_less(16.0)


func test_the_camera_view_decides_what_is_on_screen() -> void:
	var camera := Camera3D.new()
	camera.fov = 80.0
	add_child(camera)
	camera.make_current()
	camera.global_position = Vector3(0.0, 1.6, 0.0)
	var lod := _lod()
	var viewport := camera.get_viewport()
	assert_float(lod.interval_at(viewport, Vector3(0.0, 1.0, -6.0))).is_equal(0.0)
	assert_float(lod.interval_at(viewport, Vector3(0.0, 1.0, -25.0))).is_equal_approx(1.0 / 30.0, 0.0001)
	assert_float(lod.interval_at(viewport, Vector3(0.0, 1.0, 6.0))).is_equal_approx(1.0 / 10.0, 0.0001)
	camera.free()


func test_the_data_file_loads() -> void:
	var lod := BodyLod.shared()
	assert_float(lod.near_distance).is_greater(0.0)
	assert_float(lod.far_distance).is_greater(lod.near_distance)
	assert_float(lod.off_screen_rate).is_greater(0.0)

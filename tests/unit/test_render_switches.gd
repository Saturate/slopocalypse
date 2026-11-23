extends GdUnitTestSuite
## Benchmark switches: --no-shadows and --render-scale= read from the command line.


func test_shadows_are_on_unless_switched_off() -> void:
	assert_bool(RenderSwitches.no_shadows(PackedStringArray())).is_false()
	assert_bool(RenderSwitches.no_shadows(PackedStringArray(["--solo", "--no-shadows"]))).is_true()


func test_render_scale_defaults_to_full() -> void:
	assert_float(RenderSwitches.render_scale(PackedStringArray(["--solo"]))).is_equal(1.0)


func test_render_scale_reads_the_switch() -> void:
	assert_float(RenderSwitches.render_scale(PackedStringArray(["--render-scale=0.5"]))).is_equal(0.5)


func test_render_scale_is_kept_in_range() -> void:
	assert_float(RenderSwitches.render_scale(PackedStringArray(["--render-scale=0.01"]))).is_equal(RenderSwitches.MIN_SCALE)
	assert_float(RenderSwitches.render_scale(PackedStringArray(["--render-scale=9"]))).is_equal(RenderSwitches.MAX_SCALE)


func test_a_render_scale_that_is_not_a_number_is_full() -> void:
	Log.begin_capture()
	var scale := RenderSwitches.render_scale(PackedStringArray(["--render-scale=half"]))
	assert_str(LogCapture.text(Log.end_capture())).contains("--render-scale")
	assert_float(scale).is_equal(1.0)


func test_the_scale_goes_on_the_viewport() -> void:
	var viewport := SubViewport.new()
	add_child(viewport)
	RenderSwitches.apply(viewport, PackedStringArray(["--render-scale=0.5"]))
	assert_float(viewport.scaling_3d_scale).is_equal(0.5)
	viewport.queue_free()

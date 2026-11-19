extends GdUnitTestSuite
## A sample's frame time splits into scripts, physics, render and the rest, per frame; zones
## group by the module that owns them.


func test_the_split_is_per_frame_and_the_rest_is_other() -> void:
	# 100 frames of 10 ms: 300 ms of scripts, 100 of physics, 400 of render over the window.
	var b := PerfBudget.split(10.0, 100, 300_000, 100_000, 400_000)
	assert_float(float(b["frame_ms"])).is_equal(10.0)
	assert_float(float(b["scripts_ms"])).is_equal(3.0)
	assert_float(float(b["physics_ms"])).is_equal(1.0)
	assert_float(float(b["render_ms"])).is_equal(4.0)
	assert_float(float(b["other_ms"])).is_equal(2.0)


func test_parts_measured_past_the_frame_leave_no_negative_other() -> void:
	var b := PerfBudget.split(5.0, 10, 40_000, 20_000, 0)
	assert_float(float(b["other_ms"])).is_equal(0.0)


func test_no_frames_is_all_zero() -> void:
	var b := PerfBudget.split(0.0, 0, 1000, 1000, 1000)
	for key: String in ["frame_ms", "scripts_ms", "physics_ms", "render_ms", "other_ms"]:
		assert_float(float(b[key])).is_equal(0.0)


func test_zones_belong_to_their_prefix_and_event_handlers_to_the_handling_module() -> void:
	assert_str(PerfBudget.module_of("world/voxels")).is_equal("world")
	assert_str(PerfBudget.module_of("player/player_controller:physics")).is_equal("player")
	assert_str(PerfBudget.module_of("event/weapon.fired/lights")).is_equal("lights")
	assert_str(PerfBudget.module_of("event/other")).is_equal("event")
	assert_str(PerfBudget.module_of("loose")).is_equal("loose")


func test_modules_sum_their_zones_per_frame_biggest_first() -> void:
	var zones := {
		"world/voxels": {"ms": 30.0, "calls": 10, "max_ms": 5.0},
		"world/water": {"ms": 10.0, "calls": 10, "max_ms": 1.0},
		"player/player_controller:physics": {"ms": 50.0, "calls": 60, "max_ms": 2.0},
		"event/weapon.fired/world": {"ms": 20.0, "calls": 2, "max_ms": 15.0},
	}
	var m := PerfBudget.by_module(zones, 10)
	assert_array(m.keys()).contains_exactly(["world", "player"])
	assert_float(float(m["world"])).is_equal(6.0)
	assert_float(float(m["player"])).is_equal(5.0)


func test_the_line_stacks_the_parts_and_says_when_the_gpu_is_untimed() -> void:
	var b := {"frame_ms": 10.0, "scripts_ms": 3.0, "physics_ms": 1.0, "render_ms": 4.0, "other_ms": 2.0}
	assert_str(PerfBudget.line(b, 6.5)).is_equal("frame 10.0 = scripts 3.0 + physics 1.0 + render 4.0 + other 2.0   gpu 6.5")
	assert_str(PerfBudget.line(b, -1.0)).is_equal("frame 10.0 = scripts 3.0 + physics 1.0 + render 4.0 + other 2.0   gpu untimed")

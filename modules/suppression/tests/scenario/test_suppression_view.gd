extends GdUnitTestSuite
## What the suppressed player sees: the screen edges darken with their suppression and never
## reach the middle or go fully black, and each near miss shakes the view briefly unless the
## "Screen shake under fire" setting is off.

const MODULE := "res://modules/suppression/suppression_module.gd"
const SETTING := "shake_under_fire"

var _view: SuppressionView
var _camera: Camera3D
var _config: Dictionary


func before_test() -> void:
	Settings.set_value(SETTING, true)
	_config = Data.load_json((load(MODULE) as GDScript).get_script_constant_map()["CONFIG"])
	_camera = auto_free(Camera3D.new())
	add_child(_camera)
	_view = auto_free(SuppressionView.new())
	_view.config = _config
	_view.camera = _camera
	add_child(_view)


func after_test() -> void:
	Settings.set_value(SETTING, true)


func test_edges_darken_with_suppression_and_the_middle_stays_clear() -> void:
	_view.level = 0.0
	assert_float(_view.edge_alpha()).is_equal(0.0)
	_view.level = 0.5
	var half := _view.edge_alpha()
	_view.level = 1.0
	var full := _view.edge_alpha()
	assert_float(half).is_greater(0.0)
	assert_float(full).is_greater(half)
	# Never a black screen.
	assert_float(full).is_less(1.0)
	# The gradient is clear out to `clear_share` of the way to the corners.
	var gradient := _view.edge_texture().gradient
	assert_float(gradient.sample(0.0).a).is_equal(0.0)
	assert_float(gradient.sample(float(_config["vignette"]["clear_share"]) - 0.01).a).is_equal(0.0)
	assert_float(gradient.sample(1.0).a).is_greater(0.9)


func test_a_near_miss_shakes_the_view_briefly() -> void:
	_view.level = 0.8
	_view.near_miss()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(_camera.rotation.length()).is_greater(0.0)
	await get_tree().create_timer(float(_config["shake"]["seconds"]) + 0.1).timeout
	assert_vector(_camera.rotation).is_equal(Vector3.ZERO)


func test_the_setting_turns_the_shake_off() -> void:
	Settings.set_value(SETTING, false)
	_view.level = 1.0
	_view.near_miss()
	for i in 5:
		await get_tree().process_frame
		assert_vector(_camera.rotation).is_equal(Vector3.ZERO)
	# The darkened edges stay: only the shake is switched off.
	assert_float(_view.edge_alpha()).is_greater(0.0)

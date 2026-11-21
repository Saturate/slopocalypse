extends GdUnitTestSuite
## The compass strip finds what to show (#455): the base, other players by name, and nodes
## other modules put in the `compass_markers` group; it skips the local player, hidden
## markers and anything close by, sticks what is behind to an edge, and hides when turned off
## in Settings.

const CONFIG := "res://modules/compass/data/compass.json"

var _camera: Camera3D
var _me: Node3D
var _strip: CompassStrip


func before_test() -> void:
	# Looking north (-Z) from the origin.
	_camera = auto_free(Camera3D.new())
	add_child(_camera)
	_camera.current = true
	_me = _node(Vector3.ZERO)
	_me.add_to_group(&"players")
	_strip = auto_free(CompassStrip.new())
	_strip.config = Data.load_json(CONFIG)
	_strip.player = _me
	add_child(_strip)


func after_test() -> void:
	Settings.set_value("compass", true)


func _node(at: Vector3) -> Node3D:
	var n: Node3D = auto_free(Node3D.new())
	add_child(n)
	n.global_position = at
	return n


func _marker(kind: String, at: Vector3) -> Node3D:
	var n := _node(at)
	n.add_to_group(CompassStrip.GROUP)
	n.set_meta(CompassStrip.KIND_META, kind)
	return n


func _by_kind(kind: String) -> Array[Dictionary]:
	return _strip.items().filter(func(i: Dictionary) -> bool: return i["kind"] == kind)


func test_each_kind_lands_by_its_bearing() -> void:
	_marker("objective", Vector3(0, 0, -50))
	var partner := _node(Vector3(40, 0, 0))
	partner.add_to_group(&"players")
	partner.set_meta(&"player_name", "Ana")
	_strip.set_base(Vector3(-30, 5, -30))
	var objective := _by_kind("objective")
	assert_int(objective.size()).is_equal(1)
	assert_float(float(objective[0]["x"])).is_equal_approx(0.0, 0.001)
	assert_float(float(objective[0]["distance"])).is_equal_approx(50.0, 0.01)
	var ana := _by_kind("partner")
	assert_int(ana.size()).override_failure_message("the local player must not be a partner").is_equal(1)
	assert_str(str(ana[0]["label"])).is_equal("Ana")
	# Due east with half the world on the strip: the right edge, not past it.
	assert_float(float(ana[0]["x"])).is_equal_approx(1.0, 0.001)
	assert_bool(bool(ana[0]["clamped"])).is_false()
	var base := _by_kind("base")
	assert_float(float(base[0]["x"])).is_equal_approx(-0.5, 0.001)


func test_what_is_behind_sticks_to_an_edge() -> void:
	_marker("car", Vector3(-10, 0, 60))
	var car := _by_kind("car")
	assert_float(float(car[0]["x"])).is_equal(-1.0)
	assert_bool(bool(car[0]["clamped"])).is_true()


func test_turning_moves_the_markers() -> void:
	_marker("objective", Vector3(0, 0, -50))
	_camera.rotation.y = -PI / 2.0
	# Now facing east, so north is a quarter turn to the left.
	assert_float(float(_by_kind("objective")[0]["x"])).is_equal_approx(-1.0, 0.001)


func test_close_and_hidden_markers_are_left_out() -> void:
	_marker("car", Vector3(2, 0, -1))
	var hidden := _marker("objective", Vector3(0, 0, -80))
	hidden.visible = false
	assert_array(_strip.items()).is_empty()


func test_the_setting_hides_the_strip() -> void:
	Settings.set_value("compass", false)
	await get_tree().process_frame
	assert_bool(_strip.visible).is_false()
	Settings.set_value("compass", true)
	await get_tree().process_frame
	assert_bool(_strip.visible).is_true()

extends GdUnitTestSuite
## A thermal scope marks warm bodies within its range (and only while it is up), never the
## one looking, and says when it turns on and off so smoke can thin.

var _events: Array[bool] = []


func before_test() -> void:
	_events.clear()
	EventBus.subscribe(&"weapons.thermal", _on_thermal)


func after_test() -> void:
	EventBus.unsubscribe(&"weapons.thermal", _on_thermal)


func _on_thermal(p: Dictionary) -> void:
	_events.append(bool(p["on"]))


func _body(group: StringName, at: Vector3) -> MeshInstance3D:
	var body: Node3D = auto_free(Node3D.new())
	body.add_to_group(group)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	body.add_child(mesh)
	add_child(body)
	body.global_position = at
	return mesh


func test_only_a_thermal_optic_carries_thermal_settings() -> void:
	assert_float(float(ThermalView.of_build({"optic": "opt_thermal"}).get("range", 0.0))).is_greater(0.0)
	assert_dict(ThermalView.of_build({"optic": "opt_scope_4x"})).is_empty()
	assert_dict(ThermalView.of_build({})).is_empty()


func test_it_marks_warm_bodies_in_range_while_up() -> void:
	var near_soldier := _body(&"enemies", Vector3(0, 0, -20))
	var far_soldier := _body(&"enemies", Vector3(0, 0, -400))
	var drone := _body(&"warm", Vector3(10, 8, -30))
	var me := _body(&"players", Vector3.ZERO)
	var crate := _body(&"loot", Vector3(0, 0, -5))
	var view: ThermalView = auto_free(ThermalView.new())
	view.settings = {"range": 150.0}
	view.viewer = me.get_parent()
	view.eye_override = Vector3.ZERO
	add_child(view)
	view.refresh()
	# Not up yet: nothing marked by _process, and no event.
	assert_array(_events).is_empty()
	view.set_active(true)
	view.refresh()
	assert_bool(view.is_marked(near_soldier)).is_true()
	assert_bool(view.is_marked(drone)).is_true()
	assert_bool(view.is_marked(far_soldier)).is_false()
	assert_bool(view.is_marked(me)).is_false()
	assert_bool(view.is_marked(crate)).is_false()
	# Walks out of range: unmarked.
	(near_soldier.get_parent() as Node3D).global_position = Vector3(0, 0, -300)
	view.refresh()
	assert_bool(view.is_marked(near_soldier)).is_false()
	view.set_active(false)
	assert_bool(view.is_marked(drone)).is_false()
	assert_array(_events).is_equal([true, false])

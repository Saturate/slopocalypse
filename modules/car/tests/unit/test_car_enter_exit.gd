extends GdUnitTestSuite

const CAR := "res://modules/car/scenes/box_car.tscn"

var _car: CarController
var _events: Array[Dictionary] = []


func before_test() -> void:
	_car = auto_free((load(CAR) as PackedScene).instantiate())
	add_child(_car)
	_events.clear()
	EventBus.subscribe(&"car.entered", _on_entered)
	EventBus.subscribe(&"car.exited", _on_exited)


func after_test() -> void:
	EventBus.unsubscribe(&"car.entered", _on_entered)
	EventBus.unsubscribe(&"car.exited", _on_exited)


func _on_entered(p: Dictionary) -> void:
	_events.append({"type": "entered", "player": p["player"]})


func _on_exited(p: Dictionary) -> void:
	_events.append({"type": "exited", "player": p["player"], "position": p["position"]})


func _person_at(offset: Vector3) -> Node3D:
	var who: Node3D = auto_free(Node3D.new())
	add_child(who)
	who.global_position = _car.global_position + offset
	return who


func test_can_enter_when_close_and_free() -> void:
	assert_bool(_car.can_enter(_person_at(Vector3(2.0, 0.0, 0.0)))).is_true()


func test_cannot_enter_from_far_away() -> void:
	assert_bool(_car.can_enter(_person_at(Vector3(20.0, 0.0, 0.0)))).is_false()


func test_cannot_enter_an_occupied_car() -> void:
	_car.enter(_person_at(Vector3(1.0, 0.0, 0.0)))
	assert_bool(_car.can_enter(_person_at(Vector3(1.5, 0.0, 0.0)))).is_false()


func test_enter_and_exit_announce_the_driver() -> void:
	var who := _person_at(Vector3(1.0, 0.0, 0.0))
	_car.enter(who)
	assert_object(_car.driver).is_same(who)
	_car.exit_car()
	assert_object(_car.driver).is_null()
	assert_int(_events.size()).is_equal(2)
	assert_str(_events[0]["type"]).is_equal("entered")
	assert_object(_events[1]["player"]).is_same(who)


func test_exit_point_is_beside_the_car() -> void:
	var who := _person_at(Vector3(1.0, 0.0, 0.0))
	_car.enter(who)
	_car.exit_car()
	var pos: Vector3 = _events[1]["position"]
	var flat := Vector2(pos.x - _car.global_position.x, pos.z - _car.global_position.z).length()
	assert_float(flat).is_between(1.5, 3.5)


func test_exit_intent_gets_the_driver_out() -> void:
	_car.enter(_person_at(Vector3(1.0, 0.0, 0.0)))
	_car.intent().exit = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_object(_car.driver).is_null()

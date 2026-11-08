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


func test_cannot_enter_a_full_car_or_get_in_twice() -> void:
	var first := _person_at(Vector3(1.0, 0.0, 0.0))
	_car.enter(first)
	assert_bool(_car.can_enter(first)).is_false()
	_car.enter(_person_at(Vector3(-1.0, 0.0, 0.0)))
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


# Called directly, not over the network, the sender id is 0, so a driver tagged as peer 0
# stands in for "the sender is the driver".
func test_driver_intent_is_accepted_from_the_driver() -> void:
	var who := _person_at(Vector3(2.0, 0.0, 0.0))
	who.set_meta(&"peer_id", 0)
	_car.enter(who)
	_car.intent().submit(1.0, -0.5, false)
	assert_float(_car.intent().throttle).is_equal(1.0)
	assert_float(_car.intent().steer).is_equal(-0.5)


func test_driver_intent_from_anyone_else_is_ignored() -> void:
	var who := _person_at(Vector3(2.0, 0.0, 0.0))
	who.set_meta(&"peer_id", 5)
	_car.enter(who)
	Log.begin_capture()
	_car.intent().submit(1.0, 0.0, false)
	_car.intent().submit_exit()
	var logged := LogCapture.text(Log.end_capture())
	assert_float(_car.intent().throttle).is_equal(0.0)
	assert_bool(_car.intent().exit).is_false()
	assert_str(logged).contains("tried to drive")


func test_nobody_drives_an_empty_car() -> void:
	Log.begin_capture()
	_car.intent().submit(1.0, 0.0, false)
	Log.end_capture()
	assert_float(_car.intent().throttle).is_equal(0.0)


func test_a_second_person_takes_the_passenger_seat() -> void:
	var first := _person_at(Vector3(1.0, 0.0, 0.0))
	var second := _person_at(Vector3(-1.0, 0.0, 0.0))
	_car.enter(first)
	assert_bool(_car.can_enter(second)).is_true()
	_car.enter(second)
	assert_object(_car.driver).is_same(first)
	assert_object(_car.passenger).is_same(second)
	assert_bool(_car.can_enter(_person_at(Vector3(0.0, 0.0, 2.0)))).is_false()


func test_each_seat_gets_out_by_its_own_door() -> void:
	var first := _person_at(Vector3(1.0, 0.0, 0.0))
	var second := _person_at(Vector3(-1.0, 0.0, 0.0))
	_car.enter(first)
	_car.enter(second)
	_car.exit_car(second)
	assert_object(_car.passenger).is_null()
	assert_object(_car.driver).is_same(first)
	var out: Vector3 = _events[2]["position"]
	# Driver's door is on the car's left (+X facing +Z), the passenger's on the right.
	assert_float(_car.to_local(out).x).is_less(-1.0)
	_car.exit_car(first)
	assert_float(_car.to_local(_events[3]["position"]).x).is_greater(1.0)


func test_a_blocked_door_lets_you_out_the_other_side() -> void:
	await get_tree().physics_frame
	var wall: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 4.0, 6.0)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = _car.to_global(Vector3(2.2, 0.0, 0.0))
	await get_tree().physics_frame
	var who := _person_at(Vector3(1.0, 0.0, 0.0))
	_car.enter(who)
	_car.exit_car()
	assert_float(_car.to_local(_events[1]["position"]).x).is_less(-1.0)


func test_the_passenger_can_get_out_while_the_driver_stays() -> void:
	var first := _person_at(Vector3(1.0, 0.0, 0.0))
	var second := _person_at(Vector3(-1.0, 0.0, 0.0))
	_car.enter(first)
	_car.enter(second)
	_car.intent().passenger_exit = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_object(_car.passenger).is_null()
	assert_object(_car.driver).is_same(first)

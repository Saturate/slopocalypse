extends GdUnitTestSuite
## Street lamps stand along the road with their arms over it; a round on the bulb puts the
## lamp out for good (and only the bulb does), and someone joining later sees it out too.

const MODULE := "res://modules/lights/lights_module.gd"

var _events: Array[Dictionary] = []


func before_test() -> void:
	_events.clear()
	EventBus.subscribe(&"lights.lamp_broken", _on_broken)


func after_test() -> void:
	EventBus.unsubscribe(&"lights.lamp_broken", _on_broken)


func _on_broken(p: Dictionary) -> void:
	_events.append(p)


func _module() -> Node:
	var module: Node = auto_free((load(MODULE) as GDScript).new())
	add_child(module)
	module.call(&"place", [Transform3D(Basis.IDENTITY, Vector3(0, 0, -10)), Transform3D(Basis(Vector3.UP, PI), Vector3(8, 0, -40))] as Array[Transform3D])
	return module


func _bulb_point(lamp: StreetLamp) -> Vector3:
	# The underside of the bulb, as a round from the street below would strike it.
	var h := float(lamp.config["height"])
	var local := Vector3(float(lamp.config["reach"]), h - VoxStreetLamp.HEAD.y - VoxStreetLamp.BULB_SIZE.y, 0.0)
	return lamp.global_transform * local


func test_lamps_stand_beside_the_road_reaching_over_it() -> void:
	var straight := func(m: float) -> Vector3: return Vector3(0.0, 0.0, -m)
	var flat := func(_x: float, _z: float) -> float: return 2.0
	var spots: Array[Transform3D] = _road_spots(straight, flat, {"first": 10.0, "spacing": 20.0, "count": 3, "side": 5.0})
	assert_int(spots.size()).is_equal(3)
	assert_vector(spots[0].origin).is_equal_approx(Vector3(5.0, 2.0, -10.0), Vector3.ONE * 0.001)
	assert_vector(spots[1].origin).is_equal_approx(Vector3(-5.0, 2.0, -30.0), Vector3.ONE * 0.001)
	# Each arm (+x) points back across the road's middle.
	for spot in spots:
		var arm := spot.basis * Vector3.RIGHT
		assert_float(arm.dot(-Vector3(spot.origin.x, 0, 0).normalized())).is_greater(0.99)


func _road_spots(road_at: Callable, height_at: Callable, road: Dictionary) -> Array[Transform3D]:
	return (load(MODULE) as GDScript).call(&"road_spots", road_at, height_at, road)


func test_a_round_on_the_bulb_puts_the_lamp_out_and_only_the_bulb_does() -> void:
	var module := _module()
	var lamps: Array = module.get(&"lamps")
	var first: StreetLamp = lamps[0]
	var second: StreetLamp = lamps[1]
	# Into the post: nothing.
	EventBus.publish(&"weapon.fired", {"from": Vector3(0, 1, 0), "to": first.global_position + Vector3(0, 2, 0.075), "collider": first})
	assert_array(_events).is_empty()
	assert_bool(first.broken).is_false()
	EventBus.publish(&"weapon.fired", {"from": Vector3(0, 1, 0), "to": _bulb_point(second), "collider": second})
	assert_array(_events).is_equal([{"id": 1}])
	assert_bool(second.broken).is_true()
	assert_bool(second.hits_bulb(_bulb_point(second))).is_false()
	assert_bool(first.broken).is_false()


func test_someone_joining_later_sees_it_out() -> void:
	var module: Node = auto_free((load(MODULE) as GDScript).new())
	add_child(module)
	# The server's word arrives before the world is up here.
	module.call(&"apply_broken", [1])
	module.call(&"place", [Transform3D.IDENTITY, Transform3D(Basis.IDENTITY, Vector3(0, 0, -30))] as Array[Transform3D])
	var lamps: Array = module.get(&"lamps")
	assert_bool((lamps[0] as StreetLamp).broken).is_false()
	assert_bool((lamps[1] as StreetLamp).broken).is_true()

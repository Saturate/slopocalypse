extends GdUnitTestSuite
## A round into a water tower's tank below the water makes it pour, one into a leg does
## nothing, and someone joining later gets the holes and the same level.

const MODULE := "res://modules/towers/towers_module.gd"

var _events: Array[Dictionary] = []


func before_test() -> void:
	_events.clear()
	EventBus.subscribe(&"towers.holed", _on_holed)


func after_test() -> void:
	EventBus.unsubscribe(&"towers.holed", _on_holed)


func _on_holed(p: Dictionary) -> void:
	_events.append(p)


func _module() -> Node:
	var module: Node = auto_free((load(MODULE) as GDScript).new())
	add_child(module)
	module.call(&"place", [Transform3D.IDENTITY] as Array[Transform3D])
	return module


func _tank_point(t: WaterTower, up: float) -> Vector3:
	var legs := float(t.config["height"])
	return t.global_transform * Vector3(float(t.config["radius"]), legs + up, 0.0)


func test_a_round_into_the_tank_below_the_water_makes_it_pour() -> void:
	var module := _module()
	var t: WaterTower = (module.get(&"towers") as Array)[0]
	var full := t.level()
	EventBus.publish(&"weapon.fired", {"from": Vector3(20, 8, 0), "to": _tank_point(t, 0.5), "collider": t})
	assert_int(_events.size()).is_equal(1)
	assert_int(t.tank.pouring().size()).is_equal(1)
	t.tank.advance(5.0)
	assert_float(t.level()).is_less(full)


func test_a_round_near_the_top_holes_it_without_pouring() -> void:
	var module := _module()
	var t: WaterTower = (module.get(&"towers") as Array)[0]
	EventBus.publish(&"weapon.fired", {"from": Vector3(20, 8, 0), "to": _tank_point(t, float(t.config["tank"]) - 0.1), "collider": t})
	assert_int(_events.size()).is_equal(1)
	assert_int(t.tank.pouring().size()).is_equal(0)


func test_a_round_into_a_leg_does_nothing() -> void:
	var module := _module()
	var t: WaterTower = (module.get(&"towers") as Array)[0]
	var leg := float(t.config["radius"]) * 0.7
	EventBus.publish(&"weapon.fired", {"from": Vector3(20, 2, 0), "to": t.global_transform * Vector3(leg, 2.0, leg), "collider": t})
	assert_array(_events).is_empty()


func test_someone_joining_later_gets_the_holes_and_level() -> void:
	var live := _module()
	var t: WaterTower = (live.get(&"towers") as Array)[0]
	EventBus.publish(&"weapon.fired", {"from": Vector3(20, 8, 0), "to": _tank_point(t, 0.3), "collider": t})
	for i in 300:
		t.tank.advance(1.0 / 60.0)
	var late: Node = auto_free((load(MODULE) as GDScript).new())
	add_child(late)
	# The server's word arrives before the late joiner's world is up.
	late.call(&"apply_snapshot", {0: t.snapshot()})
	late.call(&"place", [Transform3D(Basis.IDENTITY, Vector3(50, 0, 0))] as Array[Transform3D])
	var copy: WaterTower = (late.get(&"towers") as Array)[0]
	assert_float(copy.level()).is_equal_approx(t.level(), 0.02)
	assert_int(copy.tank.pouring().size()).is_equal(1)

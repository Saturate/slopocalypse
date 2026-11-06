extends GdUnitTestSuite
## A stalker drone closes in and orbits its target, falls and crashes when shot down, and
## the module sends a replacement.

const MODULE := "res://modules/drones/drones_module.gd"

var _floor: StaticBody3D
var _module: Node
var _target: Node3D
var _explosions: Array[Dictionary] = []


func before_test() -> void:
	_floor = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	_floor.add_child(shape)
	add_child(_floor)
	_target = Node3D.new()
	add_child(_target)
	_module = (load(MODULE) as GDScript).new()
	add_child(_module)
	_explosions.clear()
	EventBus.subscribe(&"explosion", _on_explosion)


func after_test() -> void:
	EventBus.unsubscribe(&"explosion", _on_explosion)
	_module.free()
	_target.free()
	_floor.free()


func _on_explosion(p: Dictionary) -> void:
	_explosions.append(p)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func test_closes_in_and_orbits_at_its_radius() -> void:
	var drone: StalkerDrone = _module.server_spawn(_target)
	await _frames(60 * 12)
	var flat := Vector2(drone.global_position.x, drone.global_position.z).length()
	var radius: float = drone.config["orbit_radius"]
	assert_float(flat).is_between(radius - 4.0, radius + 4.0)
	assert_float(drone.global_position.y).is_greater(float(drone.config["min_ground_clearance"]))


func test_shot_down_drone_falls_crashes_and_is_removed() -> void:
	var drone: StalkerDrone = _module.server_spawn(_target)
	await _frames(30)
	drone.health().server_apply_damage(1000.0)
	assert_bool(drone.downed).is_true()
	await _frames(60 * 6)
	assert_bool(is_instance_valid(drone)).is_false()
	assert_int(_explosions.size()).is_equal(1)


func test_a_replacement_arrives_after_one_is_destroyed() -> void:
	_module.config["respawn_seconds"] = 0.5
	EventBus.publish(&"player.spawned", {"player": _target, "local": true})
	await _frames(90)
	assert_int(_module.drones().size()).is_equal(1)
	var first: StalkerDrone = _module.drones()[0]
	first.server_crash()
	await _frames(10)
	assert_int(_module.drones().size()).is_equal(0)
	await _frames(60)
	assert_int(_module.drones().size()).is_equal(1)
	assert_object(_module.drones()[0]).is_not_same(first)

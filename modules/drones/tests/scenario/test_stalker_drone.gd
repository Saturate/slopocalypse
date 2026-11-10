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


func test_an_angry_drone_closes_in_and_orbits_at_its_attack_radius() -> void:
	var drone: StalkerDrone = _module.server_spawn(_target)
	drone.server_anger(_target)
	drone.postpone_dive(1000.0)
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


func test_a_dive_blows_up_on_the_player_and_hurts_them() -> void:
	var player: Node3D = auto_free((load("res://modules/player/scenes/player.tscn") as PackedScene).instantiate())
	add_child(player)
	player.global_position = Vector3(30, 0.1, 30)
	var drone: StalkerDrone = _module.server_spawn(player)
	drone.global_position = player.global_position + Vector3(8, 6, 0)
	await _frames(5)
	drone.server_dive()
	await _frames(60 * 4)
	var health := player.get_node("Health") as HealthComponent
	assert_float(health.health).is_less(health.max_health)
	assert_bool(is_instance_valid(drone)).is_false()
	assert_int(_explosions.size()).is_greater(0)


func test_a_calm_drone_circles_wide_and_never_dives() -> void:
	var drone: StalkerDrone = _module.server_spawn(_target)
	var dived := false
	for i in 60 * 20:
		await get_tree().physics_frame
		dived = dived or drone.is_diving()
	assert_bool(drone.is_angry()).is_false()
	assert_bool(dived).is_false()
	var flat := Vector2(drone.global_position.x, drone.global_position.z).length()
	assert_float(flat).is_between(float(drone.config["calm_orbit_radius"]) - 5.0, float(drone.config["calm_orbit_radius"]) + 5.0)


func test_shooting_it_makes_it_angry() -> void:
	var drone: StalkerDrone = _module.server_spawn(_target)
	await _frames(5)
	drone.health().server_apply_damage(5.0)
	assert_bool(drone.is_angry()).is_true()


func _shooter_facing(drone: StalkerDrone, aim: bool) -> PlayerController:
	var player: PlayerController = auto_free((load("res://modules/player/scenes/player.tscn") as PackedScene).instantiate())
	player.add_to_group(&"players")
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector3(0, 0, 40)
	var head := player.get_node("Head") as Node3D
	drone.global_position = head.global_position + Vector3(0, 0, -30)
	drone.set_physics_process(false)
	player.intent().aim = aim
	return player


func test_holding_it_in_your_sights_makes_it_angry_and_it_comes_for_you() -> void:
	var drone: StalkerDrone = _module.server_spawn(_target)
	await _frames(2)
	var player := _shooter_facing(drone, true)
	for i in 40:
		drone.call(&"_watch_sights", 1.0 / 60.0)
	assert_bool(drone.is_angry()).is_true()
	assert_object(drone.target).is_same(player)


func test_looking_its_way_without_aiming_leaves_it_calm() -> void:
	var drone: StalkerDrone = _module.server_spawn(_target)
	await _frames(2)
	_shooter_facing(drone, false)
	for i in 120:
		drone.call(&"_watch_sights", 1.0 / 60.0)
	assert_bool(drone.is_angry()).is_false()


func test_left_alone_it_calms_down() -> void:
	var drone: StalkerDrone = _module.server_spawn(_target)
	drone.config["calm_after_seconds"] = 0.5
	drone.server_anger(_target)
	await _frames(60)
	assert_bool(drone.is_angry()).is_false()


## Ground that is 30 m high past x = 20 (a hillside) and 0 elsewhere, with no collision
## there: like the server far from players, where only the height map knows the ground.
func _add_hill() -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\nfunc surface_height(x: float, _z: float) -> float:\n\treturn 30.0 if x > 20.0 else 0.0\n"
	script.reload()
	var ground: Node = auto_free(Node.new())
	ground.set_script(script)
	ground.add_to_group(&"ground")
	add_child(ground)
	return ground


func test_drones_spawn_above_a_hillside_not_inside_it() -> void:
	_add_hill()
	for i in 16:
		var drone: StalkerDrone = _module.server_spawn(_target)
		var floor_y := 30.0 if drone.global_position.x > 20.0 else 0.0
		assert_float(drone.global_position.y).is_greater(floor_y + 5.0)


func test_a_drone_inside_the_ground_is_lifted_out() -> void:
	_add_hill()
	var drone: StalkerDrone = _module.server_spawn(_target)
	drone.postpone_dive(1000.0)
	drone.global_position = Vector3(40.0, 10.0, 0.0)
	await _frames(2)
	assert_float(drone.global_position.y).is_greater(30.0)


func test_a_downed_drone_crashes_on_the_height_map_where_there_is_no_collision() -> void:
	_add_hill()
	var drone: StalkerDrone = _module.server_spawn(_target)
	drone.global_position = Vector3(40.0, 33.0, 0.0)
	drone.health().server_apply_damage(1000.0)
	await _frames(90)
	assert_int(_explosions.size()).is_equal(1)
	assert_float((_explosions[0]["position"] as Vector3).y).is_greater(29.0)


## Something that shot: like a gun, it knows who holds it.
func _gun_held_by(holder: Node3D) -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\nvar holder: Node3D\n"
	script.reload()
	var gun: Node = auto_free(Node.new())
	gun.set_script(script)
	gun.set(&"holder", holder)
	return gun


func _shooter(at: Vector3) -> Node3D:
	var shooter: Node3D = auto_free(Node3D.new())
	shooter.add_to_group(&"players")
	add_child(shooter)
	shooter.global_position = at
	return shooter


func test_a_strike_drone_dives_into_its_spot() -> void:
	var spot := Vector3(12.0, 0.0, -8.0)
	_module.server_spawn_strike(spot)
	assert_int(_module.strike_count()).is_equal(1)
	for i in 60 * 20:
		await get_tree().physics_frame
		if not _explosions.is_empty():
			break
	assert_int(_explosions.size()).is_equal(1)
	assert_float((_explosions[0]["position"] as Vector3).distance_to(spot)).is_less(3.5)
	assert_int(_module.strike_count()).is_equal(0)


func test_shooting_a_strike_drone_turns_it_and_its_neighbours_on_you() -> void:
	var shooter := _shooter(Vector3(0, 1, 30))
	var first: StalkerDrone = _module.server_spawn_strike(Vector3(5, 0, 0))
	var second: StalkerDrone = _module.server_spawn_strike(Vector3(5, 0, 0))
	second.global_position = first.global_position + Vector3(3, 0, 0)
	first.health().server_apply_damage(5.0, _gun_held_by(shooter))
	assert_object(first.target).is_same(shooter)
	assert_object(second.target).is_same(shooter)
	assert_bool(first.is_striking()).is_false()


func test_shots_fired_near_strike_drones_draw_them() -> void:
	var drone: StalkerDrone = _module.server_spawn_strike(Vector3(5, 0, 0))
	var shooter := _shooter(drone.global_position + Vector3(0, -10, 5))
	EventBus.publish(&"weapon.fired", {"holder": shooter, "from": shooter.global_position, "to": shooter.global_position + Vector3.FORWARD})
	assert_object(drone.target).is_same(shooter)


func test_clearing_calls_off_every_strike_drone() -> void:
	_module.server_spawn_strike(Vector3(5, 0, 0))
	_module.server_spawn_strike(Vector3(-5, 0, 0))
	_module.server_clear_strikes()
	assert_int(_module.strike_count()).is_equal(0)

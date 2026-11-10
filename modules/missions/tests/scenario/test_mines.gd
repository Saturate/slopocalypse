extends GdUnitTestSuite
## Mines and tripwires: stepping close (or through a wire) sets them off after a click, a
## crouching player can disarm one, a bullet sets one off, and the cabin mission lays them.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MISSIONS := "res://modules/missions/missions_module.gd"
const SPAWN := Vector3(0.0, 1.0, 0.0)

var _missions: Node
var _player: PlayerController
var _explosions: Array = []


func before_test() -> void:
	_explosions = []
	EventBus.subscribe(&"explosion", _on_explosion)
	EventBus.subscribe(&"player.move_requested", _on_move)
	_missions = auto_free((load(MISSIONS) as GDScript).new())
	add_child(_missions)
	EventBus.publish(&"world.ready", {"spawn": SPAWN})
	_player = auto_free((load(PLAYER) as PackedScene).instantiate())
	_player.set_meta(&"peer_id", 111)
	_player.add_to_group(&"players")
	add_child(_player)
	_player.set_physics_process(false)
	_player.global_position = Vector3(20, 0, 20)


func after_test() -> void:
	EventBus.unsubscribe(&"explosion", _on_explosion)
	EventBus.unsubscribe(&"player.move_requested", _on_move)


func _on_explosion(p: Dictionary) -> void:
	_explosions.append(p)


func _on_move(p: Dictionary) -> void:
	(p["player"] as Node3D).global_position = p["position"]


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _mines() -> Array:
	return get_tree().get_nodes_in_group(&"mines").filter(func(m: Node) -> bool: return not m.is_queued_for_deletion())


func test_stepping_on_a_mine_sets_it_off_after_a_click() -> void:
	var mine: Mine = _missions.call(&"server_spawn_hazard", "mine", Vector3(0, 0, 0), Vector3.ZERO)
	await _frames(5)
	assert_int(_explosions.size()).is_equal(0)
	_player.global_position = Vector3(0.4, 0, 0)
	await _frames(3)
	assert_bool(mine.is_armed()).is_false()
	assert_int(_explosions.size()).is_equal(0)
	await _frames(60)
	assert_int(_explosions.size()).is_equal(1)
	assert_float((_player.get_node("Health") as HealthComponent).health).is_less(100.0)


func test_a_crouching_player_disarms_it() -> void:
	_missions.call(&"server_spawn_hazard", "mine", Vector3(0, 0, 0), Vector3.ZERO)
	await get_tree().process_frame
	# Close but outside the trigger radius, crouched.
	_player.global_position = Vector3(1.1, 0, 0)
	_player.intent().crouch = true
	var payload := {"player": _player}
	EventBus.publish(&"player.interact", payload)
	assert_bool(payload.get("handled", false)).is_true()
	await _frames(70)
	assert_int(_explosions.size()).is_equal(0)
	assert_int(_mines().size()).is_equal(0)


func test_a_bullet_sets_it_off() -> void:
	_missions.call(&"server_spawn_hazard", "mine", Vector3(0, 0, 0), Vector3.ZERO)
	await get_tree().process_frame
	EventBus.publish(&"weapon.fired", {"holder": _player, "from": Vector3(10, 1, 0), "to": Vector3(0.1, 0.02, 0)})
	assert_int(_explosions.size()).is_equal(1)


func test_walking_through_a_wire_sets_it_off() -> void:
	_missions.call(&"server_spawn_hazard", "wire", Vector3(-0.5, 0.3, 0), Vector3(0.5, 0.3, 0))
	await _frames(3)
	_player.global_position = Vector3(0, 0, 0.1)
	await _frames(60)
	assert_int(_explosions.size()).is_equal(1)


func test_the_cabin_mission_lays_mines_a_wire_and_signs() -> void:
	var cfg: Dictionary = _missions.get(&"config")
	var offers: Array = []
	for seed_value in 200:
		offers = (load(MISSIONS) as GDScript).call(&"roll_offers", cfg, seed_value)
		if offers.any(func(o: Dictionary) -> bool: return o.get("place", "") == "Cabin in the woods"):
			break
	_missions.set(&"offers", offers)
	var cabin: Dictionary = offers.filter(func(o: Dictionary) -> bool: return o.get("place", "") == "Cabin in the woods")[0]
	_player.global_position = SPAWN + Vector3(1, 0, 2)
	assert_bool(_missions.call(&"server_choose", 111, offers.find(cabin))).is_true()
	assert_bool(_missions.call(&"server_ride_out")).is_true()
	await get_tree().process_frame
	assert_int((_missions.get(&"buildings") as Array).size()).is_equal(1)
	var wires := _mines().filter(func(m: Node) -> bool: return (m as Mine).kind == "wire")
	assert_int(wires.size()).is_equal(1)
	assert_int(_mines().size()).is_greater(5)
	assert_int(get_tree().get_nodes_in_group(&"mine_signs").size()).is_greater(0)

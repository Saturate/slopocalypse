extends GdUnitTestSuite
## Clean Sweep: guards hold the zone's buildings, the HUD counts them down, and riding home
## pays only once the last one is down.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MISSIONS := "res://modules/missions/missions_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const ENEMIES := "res://modules/enemies/enemies_module.gd"
const SPAWN := Vector3(0.0, 1.0, 0.0)

var _missions: Node
var _player: PlayerController


func before_test() -> void:
	EventBus.subscribe(&"player.move_requested", _on_move)
	add_child(auto_free((load(INVENTORY) as GDScript).new()))
	add_child(auto_free((load(ENEMIES) as GDScript).new()))
	_missions = auto_free((load(MISSIONS) as GDScript).new())
	add_child(_missions)
	EventBus.publish(&"world.ready", {"spawn": SPAWN})
	_player = auto_free((load(PLAYER) as PackedScene).instantiate())
	_player.set_meta(&"peer_id", 71)
	_player.add_to_group(&"players")
	add_child(_player)
	_player.set_physics_process(false)
	_player.global_position = SPAWN + Vector3(1, 0, 2)
	EventBus.publish(&"player.spawned", {"player": _player, "local": false})


func after_test() -> void:
	EventBus.unsubscribe(&"player.move_requested", _on_move)


func _on_move(p: Dictionary) -> void:
	(p["player"] as Node3D).global_position = p["position"]


## Rolls boards until one offers a Clean Sweep, picks it and rides out.
func _ride_out() -> void:
	var cfg: Dictionary = _missions.get(&"config")
	for seed_value in 50:
		var offers: Array = (load(MISSIONS) as GDScript).call(&"roll_offers", cfg, seed_value)
		var sweeps := offers.filter(func(o: Dictionary) -> bool: return o["type"] == "clean_sweep")
		if not sweeps.is_empty():
			_missions.set(&"offers", offers)
			assert_bool(_missions.call(&"server_choose", 71, offers.find(sweeps[0]))).is_true()
			break
	assert_bool(_missions.call(&"server_ride_out")).is_true()
	await get_tree().process_frame


func _kind() -> MissionType:
	return _missions.get_node("Type") as MissionType


func _guards() -> Array[Node]:
	return get_tree().get_nodes_in_group(&"enemies").filter(func(n: Node) -> bool: return not n.get_meta(&"dead", false) and not n.is_queued_for_deletion())


func test_guards_take_their_posts_at_the_buildings() -> void:
	await _ride_out()
	var guards := _guards()
	assert_int(guards.size()).is_equal(int((_missions.get(&"current") as Dictionary)["guards"]))
	assert_int(int(_kind().status["left"])).is_equal(guards.size())
	var zone: Vector3 = _missions.get(&"zone")
	for g: Node in guards:
		assert_float(((g as Node3D).global_position - zone).length()).is_less(80.0)


func test_riding_home_pays_only_once_the_area_is_clear() -> void:
	await _ride_out()
	assert_bool(_kind().server_done([71])).is_false()
	for g: Node in _guards():
		(g.get_node("Health") as HealthComponent).server_apply_damage(1000.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_int(int(_kind().status["left"])).is_equal(0)
	var pay := int((_missions.get(&"current") as Dictionary)["payout"])
	var car := _missions.get(&"_dropoff_car") as Node3D
	_player.global_position = car.global_position + Vector3(2, 0, 0)
	assert_bool(_missions.call(&"server_ride_home", _player)).is_true()
	assert_int(_missions.call(&"server_tokens_of", 71)).is_equal(pay)


func test_the_last_few_are_marked() -> void:
	await _ride_out()
	var guards := _guards()
	for i in guards.size() - 2:
		(guards[i].get_node("Health") as HealthComponent).server_apply_damage(1000.0)
	for i in 70:
		await get_tree().physics_frame
	assert_int((_kind().status["spots"] as Array).size()).is_equal(2)
	assert_int(_kind().markers().size()).is_equal(2)


func test_leftover_guards_go_with_the_run() -> void:
	await _ride_out()
	var car := _missions.get(&"_dropoff_car") as Node3D
	_player.global_position = car.global_position + Vector3(2, 0, 0)
	_missions.call(&"server_ride_home", _player)
	await get_tree().process_frame
	assert_int(_guards().size()).is_equal(0)

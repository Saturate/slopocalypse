extends GdUnitTestSuite
## A mission's strike zone: the objective drive waits in a crate past the drop-off, the clock
## starts when someone walks in, and riding home with the drive pays everyone who rode home.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MISSIONS := "res://modules/missions/missions_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const SPAWN := Vector3(0.0, 1.0, 0.0)

var _missions: Node
var _inventory: Node


func before_test() -> void:
	EventBus.subscribe(&"player.move_requested", _on_move)
	_inventory = auto_free((load(INVENTORY) as GDScript).new())
	add_child(_inventory)
	_missions = auto_free((load(MISSIONS) as GDScript).new())
	add_child(_missions)
	EventBus.publish(&"world.ready", {"spawn": SPAWN})


func after_test() -> void:
	EventBus.unsubscribe(&"player.move_requested", _on_move)


## Stands in for the player module.
func _on_move(p: Dictionary) -> void:
	(p["player"] as Node3D).global_position = p["position"]


func _spawn(peer: int) -> PlayerController:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", peer)
	player.add_to_group(&"players")
	add_child(player)
	player.set_physics_process(false)
	player.global_position = SPAWN + Vector3(1, 0, 2)
	EventBus.publish(&"player.spawned", {"player": player, "local": false})
	return player


func _ride_out() -> void:
	assert_bool(_missions.call(&"server_choose", 1, 0)).is_true()
	assert_bool(_missions.call(&"server_ride_out")).is_true()
	await get_tree().process_frame


func _crate() -> LootCrate:
	return _missions.get(&"_objective_crate") as LootCrate


func test_riding_out_puts_the_drive_in_a_crate_past_the_dropoff() -> void:
	_spawn(51)
	await _ride_out()
	assert_object(_crate()).is_not_null()
	assert_array(_inventory.call(&"crate_contents", _crate())).contains_exactly(["usb_drive"])
	var dropoff: Vector3 = _missions.call(&"dropoff_of", _missions.get(&"current"))
	assert_float(_crate().global_position.z).is_less(dropoff.z - 30.0)


func test_the_clock_starts_when_someone_reaches_the_zone() -> void:
	var player := _spawn(52)
	await _ride_out()
	await get_tree().physics_frame
	assert_float(float(_missions.get(&"time_left"))).is_less(0.0)
	player.global_position = _missions.get(&"zone")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var left := float(_missions.get(&"time_left"))
	assert_float(left).is_greater(0.0)
	assert_float(left).is_less_equal(float((_missions.get(&"current") as Dictionary)["time_limit"]))


func test_riding_home_with_the_drive_pays_everyone_who_rode_home() -> void:
	var carrier := _spawn(53)
	var friend := _spawn(54)
	await _ride_out()
	var pay := int((_missions.get(&"current") as Dictionary)["payout"])
	# The carrier loots the drive out of the crate.
	carrier.global_position = _crate().global_position + Vector3(1, 0, 0)
	assert_bool(_inventory.call(&"server_open", 53, _crate())).is_true()
	assert_int(_inventory.call(&"server_take_all", 53)).is_equal(1)
	# Both walk back to the car and ride home.
	var car := _missions.get(&"_dropoff_car") as Node3D
	carrier.global_position = car.global_position + Vector3(2, 0, 0)
	friend.global_position = car.global_position + Vector3(-2, 0, 0)
	assert_bool(_missions.call(&"server_ride_home", carrier)).is_true()
	assert_int(_missions.call(&"server_tokens_of", 53)).is_equal(pay)
	assert_int(_missions.call(&"server_tokens_of", 54)).is_equal(pay)
	assert_int(_inventory.call(&"count", 53, "usb_drive")).is_equal(0)
	# The run is over and the crate is gone.
	assert_str(str(_missions.get(&"state"))).is_equal("home")
	assert_object(_crate()).is_null()


func test_riding_home_without_the_drive_pays_nothing() -> void:
	var player := _spawn(55)
	await _ride_out()
	var crate := _crate()
	var car := _missions.get(&"_dropoff_car") as Node3D
	player.global_position = car.global_position + Vector3(2, 0, 0)
	assert_bool(_missions.call(&"server_ride_home", player)).is_true()
	assert_int(_missions.call(&"server_tokens_of", 55)).is_equal(0)
	await get_tree().process_frame
	assert_bool(is_instance_valid(crate) and not crate.is_queued_for_deletion()).is_false()


func _drones() -> Node:
	var drones: Node = auto_free((load("res://modules/drones/drones_module.gd") as GDScript).new())
	add_child(drones)
	return drones


func test_strike_waves_come_on_the_clock_and_never_stop_once_time_is_up() -> void:
	var drones := _drones()
	var player := _spawn(56)
	await _ride_out()
	player.global_position = _missions.get(&"zone")
	# One tick starts the clock, the next sends the first wave.
	for i in 4:
		await get_tree().physics_frame
	var waves: Array = (_missions.get(&"config") as Dictionary)["strikes"]["waves"]
	assert_int(drones.call(&"strike_count")).is_equal(int(waves[0]["drones"]))
	# Into the second wave.
	_missions.call(&"_step_strikes", float(waves[1]["at"]), false)
	assert_int(drones.call(&"strike_count")).is_equal(int(waves[0]["drones"]) + int(waves[1]["drones"]))
	# Time up: a wave every few seconds, capped.
	_missions.set(&"time_left", 0.0)
	for i in 10:
		_missions.call(&"_step_strikes", 30.0, false)
	assert_int(drones.call(&"strike_count")).is_equal(int((_missions.get(&"config") as Dictionary)["strikes"]["max_flying"]))


func test_the_strike_ends_with_the_run() -> void:
	var drones := _drones()
	var player := _spawn(57)
	await _ride_out()
	player.global_position = _missions.get(&"zone")
	for i in 4:
		await get_tree().physics_frame
	assert_int(drones.call(&"strike_count")).is_greater(0)
	var car := _missions.get(&"_dropoff_car") as Node3D
	player.global_position = car.global_position + Vector3(2, 0, 0)
	_missions.call(&"server_ride_home", player)
	assert_int(drones.call(&"strike_count")).is_equal(0)

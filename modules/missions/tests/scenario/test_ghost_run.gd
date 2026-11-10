extends GdUnitTestSuite
## Ghost Run: the drive is in the best-guarded building (every post there manned), no clock;
## riding home with it pays.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MISSIONS := "res://modules/missions/missions_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const ENEMIES := "res://modules/enemies/enemies_module.gd"
const SPAWN := Vector3(0.0, 1.0, 0.0)

var _missions: Node
var _inventory: Node
var _player: PlayerController


func before_test() -> void:
	EventBus.subscribe(&"player.move_requested", _on_move)
	_inventory = auto_free((load(INVENTORY) as GDScript).new())
	add_child(_inventory)
	var enemies: Node = auto_free((load(ENEMIES) as GDScript).new())
	add_child(enemies)
	((enemies.get(&"config") as Dictionary)["fortitude"] as Dictionary)["start"] = [20, 20]
	_missions = auto_free((load(MISSIONS) as GDScript).new())
	add_child(_missions)
	EventBus.publish(&"world.ready", {"spawn": SPAWN})
	_player = auto_free((load(PLAYER) as PackedScene).instantiate())
	_player.set_meta(&"peer_id", 101)
	_player.add_to_group(&"players")
	add_child(_player)
	_player.set_physics_process(false)
	_player.global_position = SPAWN + Vector3(1, 0, 2)
	EventBus.publish(&"player.spawned", {"player": _player, "local": false})


func after_test() -> void:
	EventBus.unsubscribe(&"player.move_requested", _on_move)


func _on_move(p: Dictionary) -> void:
	(p["player"] as Node3D).global_position = p["position"]


func _ride_out() -> void:
	var cfg: Dictionary = _missions.get(&"config")
	for seed_value in 80:
		var offers: Array = (load(MISSIONS) as GDScript).call(&"roll_offers", cfg, seed_value)
		var runs := offers.filter(func(o: Dictionary) -> bool: return o["type"] == "ghost_run")
		if not runs.is_empty():
			_missions.set(&"offers", offers)
			assert_bool(_missions.call(&"server_choose", 101, offers.find(runs[0]))).is_true()
			break
	assert_bool(_missions.call(&"server_ride_out")).is_true()
	await get_tree().process_frame


func _kind() -> MissionType:
	return _missions.get_node("Type") as MissionType


func test_the_drive_sits_in_the_building_with_every_post_manned() -> void:
	await _ride_out()
	var crate := _kind().get(&"_crate") as Node3D
	assert_object(crate).is_not_null()
	assert_array(_inventory.call(&"crate_contents", crate)).contains_exactly(["usb_drive"])
	var guards := get_tree().get_nodes_in_group(&"enemies").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	var near := guards.filter(func(g: Node) -> bool: return (g as Node3D).global_position.distance_to(crate.global_position) < 8.0)
	assert_int(near.size()).is_greater_equal(3)
	# No clock in a Ghost Run.
	assert_bool(_kind().status.has("time_left")).is_false()


func test_riding_home_with_the_drive_pays() -> void:
	await _ride_out()
	var crate := _kind().get(&"_crate") as Node3D
	_player.global_position = crate.global_position + Vector3(0.8, 0, 0)
	assert_bool(_inventory.call(&"server_open", 101, crate)).is_true()
	assert_int(_inventory.call(&"server_take_all", 101)).is_equal(1)
	var pay := int((_missions.get(&"current") as Dictionary)["payout"])
	var car := _missions.get(&"_dropoff_car") as Node3D
	_player.global_position = car.global_position + Vector3(2, 0, 0)
	assert_bool(_missions.call(&"server_ride_home", _player)).is_true()
	assert_int(_missions.call(&"server_tokens_of", 101)).is_equal(pay)

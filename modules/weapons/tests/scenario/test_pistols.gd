extends GdUnitTestSuite
## A player with each new pistol as their sidearm. The revolver loads a round every
## `reload_seconds`, can fire with whatever is in, stops loading when fired or put away,
## and stops at six. The .50 spreads wider on the move. The local instance is the server here, so these are the
## server's rules.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"
const PEER := 43

var _module: Node
var _player: PlayerController
var _shots: Array[Dictionary] = []


func _arm(build_name: String) -> void:
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)
	# Known before the player spawns, so the gun arrives loaded rather than as a swap.
	EventBus.publish(&"weapons.build_changed", {"peer": PEER, "build": GunAssembly.build(build_name)})
	_player = auto_free((load(PLAYER) as PackedScene).instantiate())
	_player.set_meta(&"peer_id", PEER)
	_player.add_to_group(&"players")
	add_child(_player)
	_player.set_physics_process(false)
	EventBus.publish(&"player.spawned", {"player": _player, "local": false})
	_player.intent().weapon_slot = 1
	await _wait(0.1)
	# Drawing takes a moment before the first shot.
	await _wait(float(_gun().stats.get("draw_seconds", 0.0)) + 0.05)


func before_test() -> void:
	_shots.clear()
	EventBus.subscribe(&"weapon.fired", _on_fired)


func after_test() -> void:
	EventBus.unsubscribe(&"weapon.fired", _on_fired)


func _on_fired(p: Dictionary) -> void:
	if not bool(p.get("through", false)):
		_shots.append(p)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _gun() -> HitscanWeapon:
	return _player.get_node("Head/Camera/Weapon_secondary") as HitscanWeapon


## One trigger pull, then waits out the rate of fire.
func _pull(gun: HitscanWeapon) -> void:
	_player.intent().fire = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	_player.intent().fire = false
	await _wait(60.0 / float(gun.stats["rounds_per_minute"]) + 0.05)


func test_the_revolver_loads_a_round_at_a_time_and_stops_at_six() -> void:
	await _arm("python_standard")
	var gun := _gun()
	assert_bool(gun.round_by_round).is_true()
	assert_int(gun.ammo()).is_equal(6)
	for i in 3:
		await _pull(gun)
	assert_int(_shots.size()).is_equal(3)
	assert_int(gun.ammo()).is_equal(3)
	var per_round := float(gun.stats["reload_seconds"])
	_player.intent().reload = true
	await _wait(per_round * 0.5)
	assert_bool(gun.is_reloading()).is_true()
	assert_int(gun.ammo()).is_equal(3)
	await _wait(per_round)
	assert_int(gun.ammo()).is_equal(4)
	await _wait(per_round * 3.0)
	assert_int(gun.ammo()).is_equal(6)
	assert_bool(gun.is_reloading()).is_false()


func test_firing_stops_the_revolvers_reload_with_what_is_loaded() -> void:
	await _arm("python_standard")
	var gun := _gun()
	for i in 6:
		await _pull(gun)
	assert_int(gun.ammo()).is_equal(0)
	_player.intent().reload = true
	var per_round := float(gun.stats["reload_seconds"])
	await _wait(per_round * 2.5)
	assert_int(gun.ammo()).is_equal(2)
	await _pull(gun)
	assert_int(_shots.size()).is_equal(7)
	assert_bool(gun.is_reloading()).is_false()
	assert_int(gun.ammo()).is_equal(1)
	await _wait(per_round * 2.0)
	assert_int(gun.ammo()).is_equal(1)


func test_putting_the_revolver_away_stops_its_reload() -> void:
	await _arm("python_standard")
	var gun := _gun()
	for i in 4:
		await _pull(gun)
	_player.intent().reload = true
	var per_round := float(gun.stats["reload_seconds"])
	await _wait(per_round * 1.5)
	assert_int(gun.ammo()).is_equal(3)
	_player.intent().weapon_slot = 0
	await _wait(per_round * 2.0)
	assert_bool(gun.is_reloading()).is_false()
	assert_int(gun.ammo()).is_equal(3)


func test_a_magazine_pistol_reloads_all_at_once() -> void:
	await _arm("deagle_standard")
	var gun := _gun()
	assert_bool(gun.round_by_round).is_false()
	assert_int(gun.ammo()).is_equal(7)
	await _pull(gun)
	_player.intent().reload = true
	await _wait(float(gun.stats["reload_seconds"]) * 0.8)
	assert_int(gun.ammo()).is_equal(6)
	# Pulling the trigger mid-reload does nothing: the magazine is out.
	await _pull(gun)
	assert_int(_shots.size()).is_equal(1)
	await _wait(float(gun.stats["reload_seconds"]) * 0.4)
	assert_int(gun.ammo()).is_equal(7)


func test_the_eagle_spreads_wider_on_the_move() -> void:
	await _arm("deagle_standard")
	var gun := _gun()
	assert_bool(gun.is_moving()).is_false()
	var still := gun.spread_scale(false, false, gun.is_moving())
	_player.velocity = Vector3(float(gun.stats["moving_spread_speed"]) + 1.0, 0.0, 0.0)
	assert_bool(gun.is_moving()).is_true()
	var moving := gun.spread_scale(false, false, gun.is_moving())
	_player.velocity = Vector3.ZERO
	assert_float(moving).is_equal_approx(still * float(gun.stats["moving_spread_multiplier"]), 0.0001)
	assert_float(moving).is_greater(still * 1.5)


func test_receiver_handling_reaches_the_gun() -> void:
	await _arm("fn57_standard")
	var gun := _gun()
	var receiver: Dictionary = GunAssembly.catalogue()["rcv_fn57"]
	assert_float(float(gun.stats["draw_seconds"])).is_equal(float(receiver["draw_seconds"]))
	assert_float(float(gun.stats["recoil_recovery"])).is_equal(float(receiver["recoil_recovery"]))
	assert_float(float(gun.stats["moving_spread_multiplier"])).is_equal(1.0)
	assert_int(gun.ammo()).is_equal(20)

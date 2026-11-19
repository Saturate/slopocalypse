extends GdUnitTestSuite
## A player carrying the bolt-action rifle: two quick trigger pulls fire one shot, since the
## bolt has to be worked first; once it has, the next pull fires. The local instance is the
## server here, so this is the server's rule at work.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"

var _module: Node
var _player: PlayerController
var _shots: Array[Dictionary] = []


func before_test() -> void:
	GunAssembly.override_build = "bolt_standard"
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)
	_player = auto_free((load(PLAYER) as PackedScene).instantiate())
	_player.set_meta(&"peer_id", 31)
	_player.add_to_group(&"players")
	add_child(_player)
	EventBus.publish(&"player.spawned", {"player": _player, "local": false})
	_shots.clear()
	EventBus.subscribe(&"weapon.fired", _on_fired)


func after_test() -> void:
	GunAssembly.override_build = ""
	EventBus.unsubscribe(&"weapon.fired", _on_fired)


func _on_fired(p: Dictionary) -> void:
	if not bool(p.get("through", false)):
		_shots.append(p)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _pull() -> void:
	_player.intent().fire = true
	await _frames(2)
	_player.intent().fire = false
	await _frames(2)


func _gun() -> HitscanWeapon:
	return _player.get_node("Head/Camera/Weapon_primary") as HitscanWeapon


func test_two_quick_pulls_fire_once_then_again_after_the_bolt() -> void:
	var gun := _gun()
	assert_float(gun.cycle_seconds).is_greater(0.0)
	assert_bool(gun.semi_auto).is_true()
	await _frames(int(ceil(float(gun.stats.get("draw_seconds", 0.0)) * Engine.physics_ticks_per_second)) + 2)
	await _pull()
	await _pull()
	assert_int(_shots.size()).is_equal(1)
	assert_bool(gun.is_cycling()).is_true()
	await _frames(int(ceil(gun.cycle_seconds * Engine.physics_ticks_per_second)) + 2)
	assert_bool(gun.is_cycling()).is_false()
	await _pull()
	assert_int(_shots.size()).is_equal(2)
	assert_int(gun.ammo()).is_equal(3)


func _draw_wait(gun: HitscanWeapon) -> void:
	await _frames(int(ceil(float(gun.stats.get("draw_seconds", 0.0)) * Engine.physics_ticks_per_second)) + 2)


func test_from_the_hip_it_scatters_and_aimed_it_is_precise() -> void:
	var gun := _gun()
	var spread := float(gun.stats["spread_degrees"])
	assert_float(spread * gun.spread_scale(false)).is_greater(1.0)
	assert_float(spread * gun.spread_scale(true)).is_less(0.05)
	# Aimed, tighter than an aimed rifle; from the hip, far looser.
	var rifle: Dictionary = GunAssembly.assemble_named("ar_standard")["stats"]
	var rifle_aimed := float(rifle["spread_degrees"]) * float((Data.load_json(HitscanWeapon.CONFIG) as Dictionary)["rifle"]["ads_spread_multiplier"])
	assert_float(spread * gun.spread_scale(true)).is_less(rifle_aimed)
	assert_float(spread * gun.spread_scale(false)).is_greater(rifle_aimed * 5.0)


func test_every_shot_but_the_last_is_followed_by_the_bolt() -> void:
	var gun := _gun()
	await _draw_wait(gun)
	for i in 5:
		await _pull()
		await _frames(int(ceil(gun.cycle_seconds * Engine.physics_ticks_per_second)) + 2)
	assert_int(_shots.size()).is_equal(5)
	for i in 4:
		assert_bool(bool(_shots[i]["cycles"])).override_failure_message("shot %d" % i).is_true()
	assert_bool(bool(_shots[4]["cycles"])).is_false()
	assert_bool(gun.is_cycling()).is_false()


func test_a_holstered_bolt_action_finishes_its_cycle() -> void:
	var gun := _gun()
	await _draw_wait(gun)
	await _pull()
	assert_bool(gun.is_cycling()).is_true()
	_player.intent().weapon_slot = 1
	await _frames(int(ceil(gun.cycle_seconds * Engine.physics_ticks_per_second)) + 2)
	assert_bool(gun.active).is_false()
	assert_bool(gun.is_cycling()).is_false()
	_player.intent().weapon_slot = 0
	await _draw_wait(gun)
	await _pull()
	assert_int(_shots.size()).is_equal(2)

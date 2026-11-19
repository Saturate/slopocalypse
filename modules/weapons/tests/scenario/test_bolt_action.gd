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

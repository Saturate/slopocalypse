extends GdUnitTestSuite
## A player carrying the machine gun: it fires about fifteen rounds a second off a 100-round
## belt, takes a long time to draw, shoots far tighter crouched (braced) than standing, and
## slows its holder while it is out. The local instance is the server here, so these are the
## server's rules. The body is held still (no floor to land on), so it counts as on the
## ground. Only the server rolls spread; bracing just scales its seeded roll.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"

var _module: Node
var _player: PlayerController
var _shots: Array[Dictionary] = []


func before_test() -> void:
	GunAssembly.override_build = "mg_standard"
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)
	_player = auto_free((load(PLAYER) as PackedScene).instantiate())
	_player.set_meta(&"peer_id", 41)
	_player.add_to_group(&"players")
	add_child(_player)
	_player.set_physics_process(false)
	EventBus.publish(&"player.spawned", {"player": _player, "local": false})
	_shots.clear()
	EventBus.subscribe(&"weapon.fired", _on_fired)


func after_test() -> void:
	GunAssembly.override_build = ""
	EventBus.unsubscribe(&"weapon.fired", _on_fired)


func _on_fired(p: Dictionary) -> void:
	if not bool(p.get("through", false)):
		_shots.append(p)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _gun() -> HitscanWeapon:
	return _player.get_node("Head/Camera/Weapon_primary") as HitscanWeapon


func test_it_fires_about_fifteen_rounds_a_second_off_a_hundred_round_belt() -> void:
	var gun := _gun()
	assert_bool(gun.semi_auto).is_false()
	assert_int(gun.ammo()).is_equal(100)
	_player.intent().fire = true
	await _wait(1.0)
	_player.intent().fire = false
	# 900 a minute is 15 a second; the timer and the physics ticks don't line up exactly.
	assert_int(_shots.size()).is_between(10, 18)
	assert_int(gun.ammo()).is_equal(100 - _shots.size())
	gun.request_reload()
	assert_bool(gun.is_reloading()).is_true()


func test_it_is_slow_to_draw() -> void:
	var gun := _gun()
	var draw := float(gun.stats["draw_seconds"])
	assert_float(draw).is_greater(0.8)
	_player.intent().weapon_slot = 1
	await _wait(0.2)
	_player.intent().weapon_slot = 0
	_player.intent().fire = true
	await _wait(draw * 0.6)
	assert_int(_shots.size()).is_equal(0)
	await _wait(draw * 0.6)
	_player.intent().fire = false
	assert_int(_shots.size()).is_greater(0)


## The angle (degrees) of each of `count` shots off the aim, from the rules seeded with
## `roll_seed`, standing or crouched.
func _shot_angles(gun: HitscanWeapon, roll_seed: int, crouched: bool, count: int) -> Array[float]:
	gun.rules.setup(gun.stats["rounds_per_minute"], int(gun.stats["magazine"]), gun.stats["reload_seconds"], deg_to_rad(gun.stats["spread_degrees"]), 0.0, false, roll_seed)
	_player.intent().crouch = crouched
	_shots.clear()
	var aim := -gun.global_transform.basis.z
	var out: Array[float] = []
	for i in count:
		gun.server_fire(gun.global_transform.origin, aim)
		gun.rules.tick(1.0)
		var shot: Dictionary = _shots[_shots.size() - 1]
		out.append(rad_to_deg(aim.angle_to((shot["to"] as Vector3) - (shot["from"] as Vector3))))
	return out


func test_crouched_on_its_bipod_it_shoots_tighter_than_standing() -> void:
	var gun := _gun()
	assert_bool(gun.is_braced()).is_false()
	var standing := _shot_angles(gun, 4242, false, 30)
	var braced := _shot_angles(gun, 4242, true, 30)
	assert_bool(gun.is_braced()).is_true()
	var factor := float(gun.stats["braced_spread_multiplier"])
	var cone := float(gun.stats["spread_degrees"])
	var widest := 0.0
	for i in standing.size():
		widest = maxf(widest, standing[i])
		# The same seeded roll, only scaled: shot for shot, braced is the standing shot narrowed.
		assert_float(braced[i]).override_failure_message("shot %d" % i).is_equal_approx(standing[i] * factor, 0.01)
		assert_float(braced[i]).is_less_equal(cone * factor + 0.01)
	# Standing really is wide: some shots land well out in the cone.
	assert_float(widest).is_greater(cone * 0.5)


func test_creeping_along_crouched_is_not_braced() -> void:
	var gun := _gun()
	_player.intent().crouch = true
	assert_bool(gun.is_braced()).is_true()
	_player.velocity = Vector3(float(gun.stats["braced_max_speed"]) + 1.0, 0.0, 0.0)
	assert_bool(gun.is_braced()).is_false()
	_player.velocity = Vector3.ZERO
	_player.intent().crouch = false
	assert_bool(gun.is_braced()).is_false()


func test_it_slows_its_holder_while_it_is_out() -> void:
	var slower := float(GunAssembly.receiver_of(GunAssembly.build("mg_standard"))["move_speed_multiplier"])
	assert_float(slower).is_less(1.0)
	assert_float(_player.carry_speed_multiplier).is_equal_approx(slower, 0.0001)
	_player.intent().weapon_slot = 1
	await _wait(0.2)
	assert_float(_player.carry_speed_multiplier).is_equal(1.0)
	_player.intent().weapon_slot = 0
	await _wait(0.2)
	assert_float(_player.carry_speed_multiplier).is_equal_approx(slower, 0.0001)
	# Taken out of the hands (dropped, or lost on death): full pace again.
	EventBus.publish(&"weapons.build_changed", {"peer": 41, "slot": "primary", "build": {}})
	assert_float(_player.carry_speed_multiplier).is_equal(1.0)


func test_a_soldier_given_the_machine_gun_item_carries_the_machine_gun() -> void:
	var build: Dictionary = (load(MODULE) as GDScript).call(&"build_of_item", "gun_mg", {})
	assert_dict(build).is_equal(GunAssembly.build("mg_standard"))


extends GdUnitTestSuite
## Rounds from someone on another side passing close to a player build that player's
## suppression on the server, which falls back to 0 over time; rounds far off, from their own
## gun or from a teammate don't count. While it is up their own gun's spread widens. The local
## instance is the server here (peer 1), and the player is its own, so the value it sends to
## the owning client lands in this same instance.

const PLAYER := "res://modules/player/scenes/player.tscn"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const MODULE := "res://modules/suppression/suppression_module.gd"

var _module: Node
var _player: PlayerController
var _foe: Node3D
var _near: Array[Dictionary] = []


func before_test() -> void:
	add_child(auto_free((load(WEAPONS) as GDScript).new()))
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)
	_player = auto_free((load(PLAYER) as PackedScene).instantiate())
	_player.set_meta(&"peer_id", 1)
	_player.add_to_group(&"players")
	add_child(_player)
	# No floor here: held still, it stays where it was put.
	_player.set_physics_process(false)
	EventBus.publish(&"player.spawned", {"player": _player, "local": false})
	_foe = auto_free(Node3D.new())
	_foe.set_meta(&"team", "enemies")
	add_child(_foe)
	_foe.global_position = Vector3(0, 1.5, -40)
	_near.clear()
	EventBus.subscribe(&"suppression.near_miss", _on_near_miss)


func after_test() -> void:
	EventBus.unsubscribe(&"suppression.near_miss", _on_near_miss)


func _on_near_miss(p: Dictionary) -> void:
	_near.append(p)


func _level() -> float:
	return float(_module.call(&"level_of", 1))


## A round from `shooter` that passes `offset` metres to the side of the player's chest and
## carries on 40 m past them.
func _shot_past(shooter: Node, offset: float) -> void:
	var chest := _player.global_position + Vector3.UP * 1.3
	EventBus.publish(&"weapon.fired", {"weapon": null, "holder": shooter, "from": Vector3(chest.x, chest.y, -40.0), "to": Vector3(chest.x + offset, chest.y, 40.0), "target": null, "collider": null, "damage": 0.0})


func test_near_misses_build_suppression_that_wears_off() -> void:
	for i in 3:
		_shot_past(_foe, 1.0)
	var per := float((_module.get(&"config") as Dictionary)["per_near_miss"])
	assert_float(_level()).is_equal_approx(per * 3.0, 0.0001)
	# The owning client (this instance) heard about each one.
	assert_int(_near.size()).is_equal(3)
	assert_float(float(_module.call(&"local_level"))).is_equal_approx(per * 3.0, 0.01)
	var decay := float((_module.get(&"config") as Dictionary)["decay_per_second"])
	await get_tree().create_timer(per * 3.0 / decay + 0.3).timeout
	assert_float(_level()).is_equal(0.0)
	assert_float(float(_module.call(&"local_level"))).is_equal(0.0)


func test_far_shots_own_shots_and_teammates_do_not_count() -> void:
	_shot_past(_foe, 5.0)
	_shot_past(_player, 0.5)
	var mate: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	mate.set_meta(&"peer_id", 2)
	mate.add_to_group(&"players")
	add_child(mate)
	mate.set_physics_process(false)
	_shot_past(mate, 0.5)
	# No shooter known (a scripted effect, a test range's fake shot).
	_shot_past(null, 0.5)
	assert_float(_level()).is_equal(0.0)
	assert_int(_near.size()).is_equal(0)


func test_a_dead_player_is_not_suppressed_and_death_clears_it() -> void:
	_shot_past(_foe, 1.0)
	assert_float(_level()).is_greater(0.0)
	# The player module marks the dead; it isn't loaded here.
	_player.set_meta(&"dead", true)
	EventBus.publish(&"player.died", {"player": _player})
	assert_float(_level()).is_equal(0.0)
	_shot_past(_foe, 1.0)
	assert_float(_level()).is_equal(0.0)
	_player.set_meta(&"dead", false)
	EventBus.publish(&"player.respawned", {"player": _player})
	_shot_past(_foe, 1.0)
	assert_float(_level()).is_greater(0.0)


func test_spread_widens_with_suppression() -> void:
	var gun := _player.get_node("Head/Camera/Weapon_primary") as HitscanWeapon
	assert_object(gun).is_not_null()
	var calm := gun.spread_scale(false)
	assert_float(calm).is_equal(1.0)
	for i in 4:
		_shot_past(_foe, 1.0)
	# `physics_frame` comes before the step's physics callbacks: the second is after one ran.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var penalty := float((_module.get(&"config") as Dictionary)["spread_penalty"])
	var expected := 1.0 + _level() * penalty
	assert_float(_player.aim_spread_multiplier).is_equal_approx(expected, 0.02)
	assert_float(gun.spread_scale(false)).is_equal_approx(expected, 0.02)
	# Aimed or braced, the penalty multiplies what those leave.
	assert_float(gun.spread_scale(true)).is_equal_approx(float(gun.stats["ads_spread_multiplier"]) * expected, 0.02)


func test_a_round_through_a_wall_counts_once() -> void:
	var chest := _player.global_position + Vector3.UP * 1.3
	var wall := Vector3(chest.x + 0.5, chest.y, chest.z - 1.0)
	EventBus.publish(&"weapon.fired", {"weapon": null, "holder": _foe, "from": Vector3(chest.x, chest.y, -40.0), "to": wall, "target": null, "damage": 0.0})
	EventBus.publish(&"weapon.fired", {"weapon": null, "holder": _foe, "from": wall, "to": Vector3(chest.x + 1.0, chest.y, 40.0), "target": null, "damage": 0.0, "through": true})
	var per := float((_module.get(&"config") as Dictionary)["per_near_miss"])
	assert_float(_level()).is_equal_approx(per, 0.0001)
	assert_int(_near.size()).is_equal(1)


func test_a_player_parked_in_a_car_is_not_suppressed_where_they_got_in() -> void:
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_shot_past(_foe, 0.5)
	assert_float(_level()).is_equal(0.0)

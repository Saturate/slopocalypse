extends GdUnitTestSuite
## A real player holding the real rifle shoots the real dummy on flat test ground. The
## local instance is the server here (no network peer), so this exercises server_fire.

const PLAYER := "res://modules/player/scenes/player.tscn"
const RIFLE := "res://modules/weapons/scenes/rifle.tscn"
const DUMMY := "res://modules/training/scenes/dummy.tscn"

var _ground: StaticBody3D
var _player: PlayerController
var _rifle: HitscanWeapon
var _dummy: DummyTarget
var _shots: Array[Dictionary] = []


func before_test() -> void:
	_ground = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	_ground.add_child(shape)
	add_child(_ground)

	_player = (load(PLAYER) as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3.ZERO
	_rifle = (load(RIFLE) as PackedScene).instantiate()
	_rifle.holder = _player
	_player.get_node("Head/Camera").add_child(_rifle)

	# Straight ahead (-Z), torso at eye height.
	_dummy = (load(DUMMY) as PackedScene).instantiate()
	add_child(_dummy)
	_dummy.global_position = Vector3(0.0, 0.0, -10.0)

	_shots.clear()
	EventBus.subscribe(&"weapon.fired", _on_fired)


func after_test() -> void:
	EventBus.unsubscribe(&"weapon.fired", _on_fired)
	_player.free()
	_dummy.free()
	_ground.free()


func _on_fired(p: Dictionary) -> void:
	_shots.append(p)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _hold_trigger(frames: int) -> void:
	_player.intent().fire = true
	await _frames(frames)
	_player.intent().fire = false


func test_hits_a_dummy_straight_ahead() -> void:
	await _frames(10)
	_player.intent().fire = true
	await get_tree().physics_frame
	_player.intent().fire = false
	await _frames(2)
	assert_int(_shots.size()).is_equal(1)
	var damage: float = _rifle.stats["damage"]
	assert_float(_shots[0]["damage"]).is_equal(damage)
	assert_float(_dummy.health().health).is_equal(_dummy.health().max_health - damage)


func test_rate_of_fire_follows_data() -> void:
	await _frames(10)
	await _hold_trigger(60)
	var expected := float(_rifle.stats["rounds_per_minute"]) / 60.0
	assert_int(_shots.size()).is_between(int(expected) - 1, int(expected) + 1)


func test_magazine_empties_and_reload_refills() -> void:
	await _frames(10)
	# Look away so the dummy's respawn timing doesn't matter here.
	_player.rotate_y(PI)
	await _hold_trigger(240)
	assert_int(_rifle.ammo()).is_equal(0)
	_player.intent().reload = true
	var reload_frames := int(ceil(float(_rifle.stats["reload_seconds"]) * Engine.physics_ticks_per_second)) + 5
	await _frames(reload_frames)
	assert_int(_rifle.ammo()).is_equal(int(_rifle.stats["magazine"]))


func test_shooting_away_from_the_dummy_misses() -> void:
	await _frames(10)
	_player.rotate_y(PI)
	await _hold_trigger(30)
	assert_int(_shots.size()).is_greater(0)
	assert_float(_dummy.health().health).is_equal(_dummy.health().max_health)


func test_aim_recovers_most_of_the_recoil_between_bursts() -> void:
	await _frames(10)
	var head: Node3D = _player.get_node("Head")
	var before := head.rotation.x
	await _hold_trigger(30)
	await _frames(2)
	var climbed := head.rotation.x - before
	await _frames(90)
	var left := head.rotation.x - before
	assert_float(left).is_less(climbed * 0.3)


func test_recoil_lifts_the_aim() -> void:
	await _frames(10)
	var head: Node3D = _player.get_node("Head")
	var before := head.rotation.x
	await _hold_trigger(30)
	await _frames(2)
	assert_float(head.rotation.x).is_greater(before)


func test_a_teammate_in_the_way_takes_no_damage() -> void:
	var mate: PlayerController = (load(PLAYER) as PackedScene).instantiate()
	add_child(mate)
	mate.global_position = Vector3(0.0, 0.0, -4.0)
	_player.add_to_group(&"players")
	mate.add_to_group(&"players")
	await _frames(10)
	_player.intent().fire = true
	await get_tree().physics_frame
	_player.intent().fire = false
	await _frames(2)
	var health := mate.get_node("Health") as HealthComponent
	assert_float(health.health).is_equal(health.max_health)
	mate.free()


func test_the_dead_do_not_shoot() -> void:
	_player.set_meta(&"dead", true)
	await _frames(10)
	await _hold_trigger(10)
	assert_int(_shots.size()).is_equal(0)

extends GdUnitTestSuite
## Someone climbing a ladder has both hands on the rails: the server fires nothing for them,
## whether the trigger comes through their intent or straight to `server_fire`, and they
## shoot again once off it. The local instance is the server here (no network peer).

const PLAYER := "res://modules/player/scenes/player.tscn"
const RIFLE := "res://modules/weapons/scenes/rifle.tscn"
## A ladder against a wall in front of the player (-z), as in test_player_ladder.
const LADDER_TOP := 6.0

var _player: PlayerController
var _rifle: HitscanWeapon
var _owner := RefCounted.new()
var _shots: Array[Dictionary] = []


func _box(at: Vector3, size: Vector3) -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	body.collision_layer = PhysicsLayers.SOLID
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = at


func before_test() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	_box(Vector3(0, LADDER_TOP / 2.0, -0.6), Vector3(2.0, LADDER_TOP, 0.2))
	Ladders.add(_owner, Transform3D(Basis.IDENTITY, Vector3(0, LADDER_TOP / 2.0, -0.1)), Vector3(0.4, LADDER_TOP / 2.0, 0.4), Vector3.FORWARD)
	_player = (load(PLAYER) as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3(0, 0.05, 0)
	_rifle = (load(RIFLE) as PackedScene).instantiate()
	_rifle.holder = _player
	_player.get_node("Head/Camera").add_child(_rifle)
	_shots.clear()
	EventBus.subscribe(&"weapon.fired", _on_fired)


func after_test() -> void:
	EventBus.unsubscribe(&"weapon.fired", _on_fired)
	Ladders.remove(_owner)
	_player.free()


func _on_fired(p: Dictionary) -> void:
	_shots.append(p)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func test_holding_the_trigger_on_a_ladder_fires_nothing() -> void:
	_player.intent().move = Vector2(0, 1)
	await _frames(30)
	assert_bool(_player.climbing).is_true()
	for i in 30:
		# A client sends its held trigger every tick.
		_player.intent().fire = true
		await get_tree().physics_frame
	assert_int(_shots.size()).is_equal(0)


func test_the_server_refuses_a_shot_from_a_climber() -> void:
	_player.intent().move = Vector2(0, 1)
	await _frames(30)
	assert_bool(_player.climbing).is_true()
	var rounds := _rifle.ammo()
	_rifle.server_fire(_rifle.global_position, -_rifle.global_basis.z)
	assert_int(_shots.size()).is_equal(0)
	assert_int(_rifle.ammo()).is_equal(rounds)


func test_off_the_ladder_the_gun_fires_again() -> void:
	_player.intent().move = Vector2(0, 1)
	await _frames(30)
	_player.intent().move = Vector2(0, -1)
	for i in 240:
		await get_tree().physics_frame
		if not _player.climbing and _player.is_on_floor():
			break
	_player.intent().move = Vector2.ZERO
	await _frames(10)
	assert_bool(_player.climbing).is_false()
	_player.intent().fire = true
	await _frames(2)
	_player.intent().fire = false
	assert_int(_shots.size()).is_greater(0)


func test_a_trigger_held_from_the_ladder_needs_a_new_pull_on_a_pistol() -> void:
	_rifle.semi_auto = true
	_player.intent().move = Vector2(0, 1)
	await _frames(30)
	_player.intent().fire = true
	_player.intent().move = Vector2(0, -1)
	for i in 240:
		await get_tree().physics_frame
		_player.intent().fire = true
		if not _player.climbing and _player.is_on_floor():
			break
	_player.intent().move = Vector2.ZERO
	for i in 20:
		_player.intent().fire = true
		await get_tree().physics_frame
	assert_int(_shots.size()).is_equal(0)

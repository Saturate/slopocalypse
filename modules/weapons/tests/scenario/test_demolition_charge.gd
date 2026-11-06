extends GdUnitTestSuite
## A placed charge lands on the aimed surface, then explodes: damage falls off with distance
## and an `explosion` event goes out for the crater and effects.

const PLAYER := "res://modules/player/scenes/player.tscn"
const DUMMY := "res://modules/training/scenes/dummy.tscn"

var _ground: StaticBody3D
var _player: PlayerController
var _thrower: ChargeThrower
var _explosions: Array[Dictionary] = []


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
	_thrower = ChargeThrower.new()
	_thrower.holder = _player
	_thrower.charges_parent = self
	_player.add_child(_thrower)
	_explosions.clear()
	EventBus.subscribe(&"explosion", _on_explosion)


func after_test() -> void:
	EventBus.unsubscribe(&"explosion", _on_explosion)
	# Unexploded charges would go off in the next test.
	for child in get_children():
		if child is DemolitionCharge:
			child.free()
	_player.free()
	_ground.free()


func test_charge_still_explodes_after_its_owner_is_gone() -> void:
	await _frames(2)
	_thrower.server_place(Vector3(0, 1.6, 0), Vector3(0, -1, -1))
	_player.free()
	_player = (load(PLAYER) as PackedScene).instantiate()
	add_child(_player)
	await _frames(int(ceil(1.5 * Engine.physics_ticks_per_second)) + 5)
	assert_int(_explosions.size()).is_equal(1)
	assert_object(_explosions[0]["source"]).is_null()


func _on_explosion(p: Dictionary) -> void:
	_explosions.append(p)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _dummy_at(pos: Vector3) -> DummyTarget:
	var d: DummyTarget = auto_free((load(DUMMY) as PackedScene).instantiate())
	add_child(d)
	d.global_position = pos
	return d


func test_charge_lands_where_aimed() -> void:
	await _frames(2)
	var charge := _thrower.server_place(Vector3(0, 1.6, 0), Vector3(0, -0.5, -1))
	assert_object(charge).is_not_null()
	assert_float(charge.global_position.y).is_equal_approx(0.0, 0.05)
	assert_float(charge.global_position.z).is_less(-2.0)


func test_explosion_kills_close_and_spares_far() -> void:
	await _frames(2)
	var close := _dummy_at(Vector3(0, 0, -6))
	var far := _dummy_at(Vector3(0, 0, -30))
	_thrower.server_place(Vector3(0, 1.6, 0), (Vector3(0, 0, -5.5) - Vector3(0, 1.6, 0)).normalized())
	var fuse: float = _thrower.stats["fuse_seconds"]
	await _frames(int(ceil(fuse * Engine.physics_ticks_per_second)) + 5)
	assert_int(_explosions.size()).is_equal(1)
	assert_bool(close.is_down()).is_true()
	assert_float(far.health().health).is_equal(far.health().max_health)


func test_cooldown_blocks_spamming() -> void:
	await _frames(2)
	assert_object(_thrower.server_place(Vector3(0, 1.6, 0), Vector3(0, -1, -1))).is_not_null()
	assert_object(_thrower.server_place(Vector3(0, 1.6, 0), Vector3(0, -1, -1))).is_null()

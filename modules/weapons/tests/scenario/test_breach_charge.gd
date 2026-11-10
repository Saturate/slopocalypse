extends GdUnitTestSuite
## With the inventory, a charge is an item: placing one uses it up, it sticks and waits, the
## placer sets off all of theirs (and only theirs), and a bullet sets one off.

const PLAYER := "res://modules/player/scenes/player.tscn"
const INVENTORY := "res://modules/inventory/inventory_module.gd"

var _ground: StaticBody3D
var _inventory: Node
var _explosions: Array[Dictionary] = []


func before_test() -> void:
	_ground = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	_ground.add_child(shape)
	add_child(_ground)
	_inventory = auto_free((load(INVENTORY) as GDScript).new())
	add_child(_inventory)
	_explosions.clear()
	EventBus.subscribe(&"explosion", _on_explosion)


func after_test() -> void:
	EventBus.unsubscribe(&"explosion", _on_explosion)
	for node in get_tree().get_nodes_in_group(&"charges"):
		node.free()


func _on_explosion(p: Dictionary) -> void:
	_explosions.append(p)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _spawn(peer: int) -> ChargeThrower:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", peer)
	player.add_to_group(&"players")
	add_child(player)
	player.set_physics_process(false)
	EventBus.publish(&"player.spawned", {"player": player, "local": false})
	var thrower := ChargeThrower.new()
	thrower.holder = player
	thrower.charges_parent = self
	player.add_child(thrower)
	return thrower


func _charges() -> Array:
	return get_tree().get_nodes_in_group(&"charges").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())


func test_placing_uses_up_a_charge_and_none_left_places_nothing() -> void:
	var thrower := _spawn(121)
	await _frames(2)
	var have := int(_inventory.call(&"count", 121, "breach_charge"))
	assert_int(have).is_greater(0)
	for i in have:
		thrower.set(&"_cooldown", 0.0)
		assert_object(thrower.server_place(Vector3(i, 1.6, 0), Vector3(0, -1, -1))).is_not_null()
	assert_int(int(_inventory.call(&"count", 121, "breach_charge"))).is_equal(0)
	thrower.set(&"_cooldown", 0.0)
	assert_object(thrower.server_place(Vector3(5, 1.6, 0), Vector3(0, -1, -1))).is_null()


func test_a_placed_charge_waits_for_its_placer() -> void:
	var mine := _spawn(122)
	var theirs := _spawn(123)
	await _frames(2)
	mine.server_place(Vector3(0, 1.6, 0), Vector3(0, -1, -1))
	theirs.server_place(Vector3(10, 1.6, 0), Vector3(0, -1, -1))
	# Well past any fuse: nothing goes off by itself.
	await _frames(3 * Engine.physics_ticks_per_second)
	assert_int(_explosions.size()).is_equal(0)
	assert_int(mine.server_detonate()).is_equal(1)
	assert_int(_explosions.size()).is_equal(1)
	assert_int(_charges().size()).is_equal(1)


func test_a_bullet_sets_a_charge_off() -> void:
	var thrower := _spawn(124)
	add_child(auto_free((load("res://modules/weapons/weapons_module.gd") as GDScript).new()))
	await _frames(2)
	var charge := thrower.server_place(Vector3(0, 1.6, 0), Vector3(0, -1, -1))
	EventBus.publish(&"weapon.fired", {"holder": null, "from": Vector3(10, 1, 0), "to": charge.global_position + Vector3(0.1, 0, 0)})
	assert_int(_explosions.size()).is_equal(1)

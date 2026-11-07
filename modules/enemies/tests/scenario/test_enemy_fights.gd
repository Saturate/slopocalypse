extends GdUnitTestSuite
## A real enemy soldier (player body, real rifle, brain) on flat ground spots a player in
## front of it, turns, and shoots them; it ignores a player behind a wall; it carries loot
## and drops it when killed.

const PLAYER := "res://modules/player/scenes/player.tscn"
const ENEMIES := "res://modules/enemies/enemies_module.gd"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"

var _ground: StaticBody3D
var _enemies: Node
var _player: PlayerController


func before_test() -> void:
	_ground = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	_ground.add_child(shape)
	add_child(_ground)
	add_child(auto_free((load(WEAPONS) as GDScript).new()))
	if ResourceLoader.exists(INVENTORY):
		add_child(auto_free((load(INVENTORY) as GDScript).new()))
	_enemies = auto_free((load(ENEMIES) as GDScript).new())
	add_child(_enemies)
	_player = auto_free((load(PLAYER) as PackedScene).instantiate())
	_player.set_meta(&"peer_id", 1)
	_player.add_to_group(&"players")
	add_child(_player)
	EventBus.publish(&"player.spawned", {"player": _player, "local": false})


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _enemy_at(at: Vector3) -> PlayerController:
	var squad: Array[Node] = _enemies.call(&"server_spawn_squad", 1, at)
	await get_tree().process_frame
	var enemy := squad[0] as PlayerController
	# Spawned with a random offset; put it exactly where the test wants it, facing -Z.
	enemy.global_position = at + Vector3.UP * 0.1
	return enemy


func test_spots_a_player_in_front_and_shoots_them() -> void:
	_player.global_position = Vector3(0, 0.1, -15)
	await _enemy_at(Vector3(0, 0, 0))
	await _frames(300)
	var health := _player.get_node("Health") as HealthComponent
	assert_float(health.health).is_less(health.max_health)


func test_a_wall_hides_the_player() -> void:
	_player.global_position = Vector3(0, 0.1, -15)
	var wall: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 6.0, 0.5)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = Vector3(0, 3, -7)
	var enemy := await _enemy_at(Vector3(0, 0, 0))
	await _frames(120)
	var brain := enemy.get_node("Brain") as EnemyBrain
	assert_object(brain.target).is_null()
	var health := _player.get_node("Health") as HealthComponent
	assert_float(health.health).is_equal(health.max_health)


func test_killing_one_drops_what_it_carried() -> void:
	if not ResourceLoader.exists(INVENTORY):
		return
	_player.global_position = Vector3(60, 0.1, 60)
	var enemy := await _enemy_at(Vector3(0, 0, 0))
	var before := get_tree().get_nodes_in_group(&"loot").size()
	(enemy.get_node("Health") as HealthComponent).server_apply_damage(1000.0)
	await get_tree().process_frame
	assert_bool(enemy.get_meta(&"dead", false)).is_true()
	assert_int(get_tree().get_nodes_in_group(&"loot").size()).is_greater(before)

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
	# Brave by default, so the fighting tests are not about fear; fear tests lower it.
	((_enemies.get(&"config") as Dictionary)["fortitude"] as Dictionary)["start"] = [20, 20]
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


## Playtest: guards shot at players they couldn't see. Leaves only had collision at the
## trunk, so a guard's eyes went straight through a tree's crown.
func test_leaves_hide_the_player_too() -> void:
	_player.global_position = Vector3(0, 0.1, -15)
	var leaves: StaticBody3D = auto_free(StaticBody3D.new())
	leaves.collision_layer = PhysicsLayers.SIGHT
	leaves.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 6.0, 2.0)
	shape.shape = box
	leaves.add_child(shape)
	add_child(leaves)
	leaves.global_position = Vector3(0, 3, -7)
	var enemy := await _enemy_at(Vector3(0, 0, 0))
	await _frames(180)
	var brain := enemy.get_node("Brain") as EnemyBrain
	assert_object(brain.target).is_null()
	var health := _player.get_node("Health") as HealthComponent
	assert_float(health.health).is_equal(health.max_health)


func test_killing_one_leaves_a_body_with_what_it_carried() -> void:
	if not ResourceLoader.exists(INVENTORY):
		return
	_player.global_position = Vector3(60, 0.1, 60)
	var enemy := await _enemy_at(Vector3(0, 0, 0))
	var before := get_tree().get_nodes_in_group(&"loot_bodies").size()
	(enemy.get_node("Health") as HealthComponent).server_apply_damage(1000.0)
	await get_tree().process_frame
	assert_bool(enemy.get_meta(&"dead", false)).is_true()
	assert_int(get_tree().get_nodes_in_group(&"loot_bodies").size()).is_equal(before + 1)


func test_a_guard_holds_its_post_and_watches_its_arc() -> void:
	_player.global_position = Vector3(80, 0.1, 80)
	var post := Vector3(4, 0, -6)
	var guard: PlayerController = _enemies.call(&"server_spawn_guard", post, 0.5)
	await _frames(60 * 6)
	assert_float(Vector2(guard.global_position.x - post.x, guard.global_position.z - post.z).length()).is_less(1.6)
	var brain := guard.get_node("Brain") as EnemyBrain
	assert_bool(brain.has_post).is_true()
	assert_float(absf(angle_difference(guard.rotation.y, 0.5))).is_less(deg_to_rad(40.0))


func test_a_patrol_walks_its_route() -> void:
	_player.global_position = Vector3(80, 0.1, 80)
	var route: Array = [Vector3(0, 0, 0), Vector3(10, 0, 0)]
	var guard: PlayerController = _enemies.call(&"server_spawn_guard", route[0], 0.0, route)
	var reached_far := false
	for i in 60 * 15:
		await get_tree().physics_frame
		if guard.global_position.distance_to(route[1]) < 2.0:
			reached_far = true
			break
	assert_bool(reached_far).is_true()


func _brain(enemy: PlayerController) -> EnemyBrain:
	return enemy.get_node("Brain") as EnemyBrain


func test_near_misses_pin_a_soldier_and_it_wears_off() -> void:
	_player.global_position = Vector3(0, 0.1, -40)
	var enemy := await _enemy_at(Vector3(0, 0, 0))
	var brain := _brain(enemy)
	var chest := enemy.global_position + Vector3.UP * 1.3
	for i in 6:
		EventBus.publish(&"weapon.fired", {"holder": _player, "from": _player.global_position + Vector3.UP * 1.5, "to": chest + Vector3(1.0, 0.0, 3.0)})
	assert_bool(brain.is_pinned()).is_true()
	await _frames(60 * 6)
	assert_bool(brain.is_pinned()).is_false()


func test_a_shot_far_off_does_not_pin() -> void:
	var enemy := await _enemy_at(Vector3(0, 0, 0))
	for i in 10:
		EventBus.publish(&"weapon.fired", {"holder": _player, "from": Vector3(30, 1, 0), "to": Vector3(30, 1, -50)})
	assert_float(_brain(enemy).suppression).is_equal(0.0)


func test_no_shot_through_a_wall() -> void:
	_player.global_position = Vector3(0, 0.1, -12)
	var enemy := await _enemy_at(Vector3(0, 0, 0))
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 4, 0.4)
	shape.shape = box
	wall.add_child(shape)
	add_child(auto_free(wall))
	wall.global_position = Vector3(0, 1.5, -6)
	await get_tree().physics_frame
	assert_bool(_brain(enemy).clear_shot(_player)).is_false()
	wall.global_position = Vector3(30, 1.5, -6)
	await get_tree().physics_frame
	assert_bool(_brain(enemy).clear_shot(_player)).is_true()


func test_a_frightened_soldier_runs_from_you() -> void:
	_player.global_position = Vector3(0, 0.1, -20)
	var enemy := await _enemy_at(Vector3(0, 0, 0))
	# Alone it loses 2: 8 becomes 6, the flee band.
	_brain(enemy).fortitude_start = 8
	var start := enemy.global_position.distance_to(_player.global_position)
	await _frames(60 * 4)
	assert_str(_brain(enemy).mood).is_equal(Fortitude.FLEE)
	assert_float(enemy.global_position.distance_to(_player.global_position)).is_greater(start + 3.0)


func test_a_soldier_with_nothing_left_gives_up_and_stops_shooting() -> void:
	_player.global_position = Vector3(0, 0.1, -15)
	var enemy := await _enemy_at(Vector3(0, 0, 0))
	# Alone and wounded: 6 - 2 - 2 = 2, the submit band.
	_brain(enemy).fortitude_start = 6
	(enemy.get_node("Health") as HealthComponent).server_apply_damage(50.0)
	await _frames(60 * 2)
	assert_bool(_brain(enemy).surrendered).is_true()
	assert_bool(enemy.get_meta(&"surrendered", false)).is_true()
	var health := _player.get_node("Health") as HealthComponent
	var before := health.health
	await _frames(60 * 3)
	assert_float(health.health).is_equal(before)


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	add_child(auto_free(wall))
	wall.global_position = at
	return wall


func test_under_fire_a_soldier_gets_behind_cover() -> void:
	_player.global_position = Vector3(0, 0.1, -20)
	# A low wall a few metres off to the side, between the soldier's side and the player.
	_box(Vector3(3, 0.6, -1.5), Vector3(2.4, 1.2, 0.3))
	await get_tree().physics_frame
	var enemy := await _enemy_at(Vector3(0, 0, 0))
	var brain := _brain(enemy)
	await _frames(60 * 5)
	assert_bool(brain.has_cover()).is_true()
	assert_bool(brain.hidden_at(brain.cover_spot(), _player.global_position)).is_true()
	assert_float(Vector2(enemy.global_position.x - brain.cover_spot().x, enemy.global_position.z - brain.cover_spot().z).length()).is_less(1.5)


func test_out_in_the_open_it_fights_where_it_stands() -> void:
	_player.global_position = Vector3(0, 0.1, -20)
	var enemy := await _enemy_at(Vector3(0, 0, 0))
	await _frames(60 * 2)
	assert_bool(_brain(enemy).has_cover()).is_false()


func test_a_soldier_who_spots_you_calls_it_out() -> void:
	_player.global_position = Vector3(0, 0.1, -20)
	var spotter := await _enemy_at(Vector3(0, 0, 0))
	var mate := await _enemy_at(Vector3(8, 0, 6))
	# The mate looks the other way and cannot see the player itself.
	mate.rotation.y = PI
	(mate.get_node("Brain") as EnemyBrain).set(&"_yaw", PI)
	await _frames(30)
	assert_object(_brain(spotter).target).is_same(_player)
	assert_object(_brain(mate).target).is_same(_player)

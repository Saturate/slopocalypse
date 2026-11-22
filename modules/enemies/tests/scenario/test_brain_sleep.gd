extends GdUnitTestSuite
## Real soldiers and civilians with BrainSleep: far from every player they stand still and
## don't think; a player coming near wakes them; a shot or a blast wakes a sleeper at once,
## and one with a fight on stays awake however far the players are.

const PLAYER := "res://modules/player/scenes/player.tscn"
const ENEMIES := "res://modules/enemies/enemies_module.gd"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"

var _enemies: Node
var _sleep: BrainSleep


func before_test() -> void:
	var ground: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	add_child(ground)
	add_child(auto_free((load(WEAPONS) as GDScript).new()))
	add_child(auto_free((load(INVENTORY) as GDScript).new()))
	_enemies = auto_free((load(ENEMIES) as GDScript).new())
	add_child(_enemies)
	_sleep = auto_free(BrainSleep.new())
	add_child(_sleep)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _soldier(at := Vector3.ZERO) -> PlayerController:
	var squad: Array[Node] = _enemies.call(&"server_spawn_squad", 1, at)
	await get_tree().process_frame
	var enemy := squad[0] as PlayerController
	enemy.global_position = at + Vector3.UP * 0.1
	await _frames(30)
	return enemy


func _player(at: Vector3) -> PlayerController:
	var p: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	p.set_meta(&"peer_id", 1)
	p.add_to_group(&"players")
	add_child(p)
	p.global_position = at
	# Held still: only where it stands matters here.
	p.set_physics_process(false)
	return p


func test_a_soldier_with_nobody_near_sleeps_and_stands_still() -> void:
	var enemy := await _soldier()
	_sleep.update()
	assert_bool(BrainSleep.is_asleep(enemy)).is_true()
	assert_bool(enemy.is_physics_processing()).is_false()
	var at := enemy.global_position
	await _frames(120)
	assert_float(enemy.global_position.distance_to(at)).is_less(0.01)


func test_a_player_coming_near_wakes_it_and_leaving_puts_it_back_to_sleep() -> void:
	var enemy := await _soldier()
	var player := _player(Vector3(0, 0.1, 1000))
	_sleep.update()
	assert_bool(BrainSleep.is_asleep(enemy)).is_true()
	player.global_position = Vector3(0, 0.1, _sleep.distance - 10.0)
	_sleep.update()
	assert_bool(BrainSleep.is_asleep(enemy)).is_false()
	assert_bool(enemy.is_physics_processing()).is_true()
	# Between distance and distance + margin it stays as it is.
	player.global_position = Vector3(0, 0.1, _sleep.distance + _sleep.margin * 0.5)
	_sleep.update()
	assert_bool(BrainSleep.is_asleep(enemy)).is_false()
	player.global_position = Vector3(0, 0.1, _sleep.distance + _sleep.margin + 10.0)
	_sleep.update()
	assert_bool(BrainSleep.is_asleep(enemy)).is_true()


func test_a_sleeping_soldier_shot_at_wakes_at_once_and_stays_awake_in_the_fight() -> void:
	var enemy := await _soldier()
	var shooter := _player(Vector3(0, 0.1, 1000))
	_sleep.update()
	assert_bool(BrainSleep.is_asleep(enemy)).is_true()
	var chest := enemy.global_position + Vector3.UP * EnemyBrain.CHEST
	EventBus.publish(&"weapon.fired", {"holder": shooter, "from": shooter.global_position, "to": chest, "damage": 10.0})
	var brain := enemy.get_node("Brain") as EnemyBrain
	assert_bool(BrainSleep.is_asleep(enemy)).is_false()
	assert_object(brain.target).is_same(shooter)
	# The shooter is far past the sleep distance, but it has a fight on.
	_sleep.update()
	assert_bool(BrainSleep.is_asleep(enemy)).is_false()


func test_a_blast_nearby_wakes_a_sleeping_soldier() -> void:
	var enemy := await _soldier()
	_sleep.update()
	assert_bool(BrainSleep.is_asleep(enemy)).is_true()
	EventBus.publish(&"explosion", {"position": enemy.global_position + Vector3(2, 0, 0), "radius": 2.0})
	assert_bool(BrainSleep.is_asleep(enemy)).is_false()


func test_a_sleeping_civilian_wakes_and_runs_at_gunfire() -> void:
	var c: PlayerController = _enemies.call(&"server_spawn_civilian", Vector3.ZERO, 0.0, [Vector3(0, 0, 12)])
	await get_tree().process_frame
	var brain := c.get_node("Brain") as CivilianBrain
	brain.config["freeze_share"] = 0.0
	_sleep.update()
	assert_bool(BrainSleep.is_asleep(c)).is_true()
	EventBus.publish(&"weapon.fired", {"from": Vector3(0, 0, -30), "to": Vector3(0, 0, -25), "damage": 0.0})
	assert_bool(BrainSleep.is_asleep(c)).is_false()
	assert_int(brain.state).is_equal(CivilianBrain.State.FLEE)
	_sleep.update()
	assert_bool(BrainSleep.is_asleep(c)).is_false()
	var at := c.global_position
	await _frames(60)
	assert_float(c.global_position.distance_to(at)).is_greater(0.5)


func test_a_dead_soldier_is_never_woken() -> void:
	var enemy := await _soldier()
	(enemy.get_node("Health") as HealthComponent).server_apply_damage(1000.0, null)
	_player(Vector3(0, 0.1, 5))
	_sleep.update()
	assert_bool(enemy.is_physics_processing()).is_false()

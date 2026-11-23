extends GdUnitTestSuite
## The server fills the map with soldiers one a physics tick, never a squad at once: each one
## costs milliseconds to set up, and a squad landing in one tick stalled the server (and with
## it every player's own movement) when a session started.

const ENEMIES := "res://modules/enemies/enemies_module.gd"
const WEAPONS := "res://modules/weapons/weapons_module.gd"

var _enemies: Node


func before_test() -> void:
	var ground := auto_free(StaticBody3D.new()) as StaticBody3D
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000.0, 1.0, 4000.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	add_child(ground)
	add_child(auto_free((load(WEAPONS) as GDScript).new()))
	_enemies = auto_free((load(ENEMIES) as GDScript).new())
	add_child(_enemies)
	var config := (_enemies.get(&"config") as Dictionary)
	config["first_spawn_seconds"] = 0.0
	config["max_alive"] = 7.0
	config["squad_size"] = [3, 3]


func test_the_first_fill_adds_one_soldier_a_tick_up_to_max_alive() -> void:
	EventBus.publish(&"world.ready", {"spawn": Vector3.ZERO})
	var counts: Array[int] = []
	for i in 30:
		await get_tree().physics_frame
		counts.append(get_tree().get_nodes_in_group(&"enemies").size())
	for i in range(1, counts.size()):
		assert_int(counts[i] - counts[i - 1]).is_less_equal(1)
	assert_int(counts[-1]).is_equal(7)


func test_respawned_squads_land_one_a_tick_and_never_pass_max_alive() -> void:
	(_enemies.get(&"config") as Dictionary)["squad_respawn_seconds"] = 0.1
	EventBus.publish(&"world.ready", {"spawn": Vector3.ZERO})
	for i in 30:
		await get_tree().physics_frame
	# Two die: the respawn timer brings in a squad to fill the gap.
	var soldiers := get_tree().get_nodes_in_group(&"enemies")
	for i in 2:
		(soldiers[i].get_node("Health") as HealthComponent).server_apply_damage(1000.0)
		soldiers[i].free()
	var counts: Array[int] = [get_tree().get_nodes_in_group(&"enemies").size()]
	for i in 30:
		await get_tree().physics_frame
		counts.append(get_tree().get_nodes_in_group(&"enemies").size())
	for i in range(1, counts.size()):
		assert_int(counts[i] - counts[i - 1]).is_less_equal(1)
		assert_int(counts[i]).is_less_equal(7)
	assert_int(counts[-1]).is_equal(7)


func test_a_squad_asked_for_directly_lands_all_at_once() -> void:
	var squad: Array[Node] = _enemies.call(&"server_spawn_squad", 3, Vector3.ZERO)
	assert_int(squad.size()).is_equal(3)
	assert_int(get_tree().get_nodes_in_group(&"enemies").size()).is_equal(3)

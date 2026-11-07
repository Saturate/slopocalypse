extends GdUnitTestSuite
## Players die when their health runs out: everyone sees them go down (hidden, not
## hittable, not moving) and they come back at the spawn at full health.

const MODULE := "res://modules/player/player_module.gd"

var _module: Node


func before_test() -> void:
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)
	EventBus.publish(&"world.ready", {"spawn": Vector3(0, 1, 0)})
	await get_tree().process_frame


func _player() -> PlayerController:
	return _module.call(&"players")[0]


func test_running_out_of_health_kills_and_respawn_restores() -> void:
	var player := _player()
	var health := player.get_node("Health") as HealthComponent
	assert_float(health.health).is_equal(health.max_health)
	var died := []
	var on_died := func(p: Dictionary) -> void: died.append(p)
	EventBus.subscribe(&"player.died", on_died)
	health.server_apply_damage(health.max_health + 5.0)
	EventBus.unsubscribe(&"player.died", on_died)
	assert_int(died.size()).is_equal(1)
	assert_bool(player.get_meta(&"dead", false)).is_true()
	assert_bool((player.get_node("Body") as Node3D).visible).is_false()
	assert_bool(player.is_physics_processing()).is_false()
	player.global_position = Vector3(40, 1, 40)
	_module.call(&"server_respawn", player)
	assert_bool(player.get_meta(&"dead", true)).is_false()
	assert_float(health.health).is_equal(health.max_health)
	assert_float(Vector2(player.global_position.x, player.global_position.z).length()).is_less(10.0)
	assert_bool(player.is_physics_processing()).is_true()


func test_dying_twice_counts_once() -> void:
	var player := _player()
	var health := player.get_node("Health") as HealthComponent
	var died := []
	var on_died := func(p: Dictionary) -> void: died.append(p)
	EventBus.subscribe(&"player.died", on_died)
	health.server_apply_damage(500.0)
	health.server_apply_damage(500.0)
	EventBus.unsubscribe(&"player.died", on_died)
	assert_int(died.size()).is_equal(1)

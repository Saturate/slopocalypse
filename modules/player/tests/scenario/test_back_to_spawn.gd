extends GdUnitTestSuite
## "Back to spawn" from the Esc menu: the server puts the player back at the spawn with
## their health and gear as they were, gets them out of a car first, and won't do it again
## until a cooldown has passed.

const MODULE := "res://modules/player/player_module.gd"

var _module: Node


func before_test() -> void:
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)
	EventBus.publish(&"world.ready", {"spawn": Vector3(0, 1, 0)})
	await get_tree().process_frame


func _player() -> PlayerController:
	return _module.call(&"players")[0]


func _near_spawn(player: PlayerController) -> bool:
	return Vector2(player.global_position.x, player.global_position.z).length() < 6.0


func test_asking_puts_you_back_at_the_spawn_keeping_your_health() -> void:
	var player := _player()
	var health := player.get_node("Health") as HealthComponent
	health.server_apply_damage(30.0)
	player.global_position = Vector3(300, 40, -900)
	# What the Esc menu button does on the player's own instance.
	EventBus.publish(&"session.back_to_spawn", {})
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(_near_spawn(player)).is_true()
	assert_float(health.health).is_equal_approx(health.max_health - 30.0, 0.01)


func test_it_waits_out_a_cooldown() -> void:
	var player := _player()
	assert_bool(_module.call(&"server_back_to_spawn", player)).is_true()
	player.global_position = Vector3(300, 40, -900)
	assert_bool(_module.call(&"server_back_to_spawn", player)).is_false()
	assert_bool(_near_spawn(player)).is_false()


func test_the_dead_cannot_use_it() -> void:
	var player := _player()
	(player.get_node("Health") as HealthComponent).server_apply_damage(1000.0)
	player.global_position = Vector3(300, 40, -900)
	assert_bool(_module.call(&"server_back_to_spawn", player)).is_false()


func test_it_gets_you_out_of_the_car_first() -> void:
	var player := _player()
	var left := []
	var on_leave := func(p: Dictionary) -> void: left.append(p.get("player"))
	EventBus.subscribe(&"player.back_to_spawn", on_leave)
	_module.call(&"server_back_to_spawn", player)
	EventBus.unsubscribe(&"player.back_to_spawn", on_leave)
	# The car module listens for this and lets them out before they are moved.
	assert_array(left).contains_exactly([player])

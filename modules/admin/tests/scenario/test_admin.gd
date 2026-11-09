extends GdUnitTestSuite
## The admin panel's server side: only admins get through, and each action reaches the
## module that does it (time, heal, god mode, teleport, spawning).

const ADMIN := "res://modules/admin/admin_module.gd"
const PLAYERS := "res://modules/player/player_module.gd"
const DAYTIME := "res://modules/daytime/daytime_module.gd"

var _admin: Node
var _players: Node


func before_test() -> void:
	_players = auto_free((load(PLAYERS) as GDScript).new())
	add_child(_players)
	_admin = auto_free((load(ADMIN) as GDScript).new())
	add_child(_admin)
	EventBus.publish(&"world.ready", {"spawn": Vector3(0, 1, 0)})
	await get_tree().process_frame


func _player() -> PlayerController:
	return _players.call(&"players")[0]


func test_strangers_are_refused() -> void:
	assert_bool(_admin.call(&"is_admin", 1)).is_true()
	assert_bool(_admin.call(&"is_admin", 4242)).is_false()
	Log.begin_capture()
	var done: bool = _admin.call(&"server_run", 4242, "heal", {})
	Log.end_capture()
	assert_bool(done).is_false()


func test_setting_the_time_reaches_the_day_and_night_cycle() -> void:
	var daytime: Node = auto_free((load(DAYTIME) as GDScript).new())
	add_child(daytime)
	assert_bool(_admin.call(&"server_run", 1, "hour", {"hour": 21.5})).is_true()
	assert_float((daytime.call(&"clock") as DayClock).hour).is_equal_approx(21.5, 0.01)


func test_heal_fills_health_back_up() -> void:
	var health := _player().get_node("Health") as HealthComponent
	health.server_apply_damage(60.0)
	_admin.call(&"server_run", int(_player().get_meta(&"peer_id")), "heal", {})
	assert_float(health.health).is_equal(health.max_health)


func test_god_mode_takes_no_damage_until_switched_off() -> void:
	var peer := int(_player().get_meta(&"peer_id"))
	var health := _player().get_node("Health") as HealthComponent
	_admin.call(&"server_run", peer, "god", {"on": true})
	health.server_apply_damage(500.0)
	assert_float(health.health).is_equal(health.max_health)
	_admin.call(&"server_run", peer, "god", {"on": false})
	health.server_apply_damage(10.0)
	assert_float(health.health).is_equal(health.max_health - 10.0)


func test_teleport_ahead_moves_you_forward() -> void:
	var player := _player()
	var start := player.global_position
	_admin.call(&"server_run", int(player.get_meta(&"peer_id")), "teleport", {"to": "ahead"})
	var moved := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	assert_float(moved).is_equal_approx(float(_admin.get(&"config")["teleport_ahead"]), 1.0)


func test_spawning_asks_the_owning_module_in_front_of_you() -> void:
	var player := _player()
	var asked := []
	var on_spawn := func(p: Dictionary) -> void: asked.append(p)
	EventBus.subscribe(&"admin.spawn", on_spawn)
	_admin.call(&"server_run", int(player.get_meta(&"peer_id")), "spawn", {"kind": "crate"})
	Log.begin_capture()
	_admin.call(&"server_run", int(player.get_meta(&"peer_id")), "spawn", {"kind": "nuke"})
	Log.end_capture()
	EventBus.unsubscribe(&"admin.spawn", on_spawn)
	assert_int(asked.size()).is_equal(1)
	assert_str(str(asked[0]["kind"])).is_equal("crate")
	var at: Vector3 = asked[0]["position"]
	var away := Vector2(at.x - player.global_position.x, at.z - player.global_position.z).length()
	assert_float(away).is_equal_approx(float(_admin.get(&"config")["spawn_ahead"]), 0.5)

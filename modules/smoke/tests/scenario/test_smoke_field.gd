extends GdUnitTestSuite
## The server's smoke: blasts start plumes, the oldest goes first past the cap, plumes end
## on their own, and a real soldier loses sight of a player behind thick smoke until it
## thins.

const PLAYER := "res://modules/player/scenes/player.tscn"
const ENEMIES := "res://modules/enemies/enemies_module.gd"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const SMOKE := "res://modules/smoke/smoke_module.gd"

var _field: SmokeField
var _ended: Array[int] = []
var _spawned: Array[Dictionary] = []


func before_test() -> void:
	var module: Node = auto_free((load(SMOKE) as GDScript).new())
	add_child(module)
	_field = module.get_node("Field") as SmokeField
	# Still air, so where a plume sits doesn't hang on the tuned wind.
	_field.config["wind"] = [0.0, 0.0]
	_field.config["rise_speed"] = 0.0
	_ended.clear()
	_spawned.clear()
	EventBus.subscribe(&"smoke.ended", _on_ended)
	EventBus.subscribe(&"smoke.spawned", _on_spawned)


func after_test() -> void:
	EventBus.unsubscribe(&"smoke.ended", _on_ended)
	EventBus.unsubscribe(&"smoke.spawned", _on_spawned)


func _on_ended(p: Dictionary) -> void:
	_ended.append(int(p["id"]))


func _on_spawned(p: Dictionary) -> void:
	_spawned.append(p)


func test_a_blast_starts_a_plume_the_clients_are_told_about() -> void:
	EventBus.publish(&"explosion", {"position": Vector3(3, 0, 4), "radius": 4.0, "source": null})
	EventBus.publish(&"explosion", {"position": Vector3(9, 0, 4), "radius": 3.0, "source": null, "kind": "drone"})
	assert_int(_field.volumes.size()).is_equal(2)
	assert_str(_field.volumes[0].source).is_equal("blast")
	assert_str(_field.volumes[1].source).is_equal("drone")
	assert_int(_spawned.size()).is_equal(2)
	assert_vector(_spawned[0]["position"] as Vector3).is_equal(Vector3(3, 0, 4))


func test_past_the_cap_the_oldest_goes_first() -> void:
	_field.config["max_volumes"] = 3.0
	var first := _field.server_spawn("blast", Vector3.ZERO)
	var second := _field.server_spawn("blast", Vector3.ZERO)
	_field.server_spawn("blast", Vector3.ZERO)
	_field.server_spawn("blast", Vector3.ZERO)
	assert_int(_field.volumes.size()).is_equal(3)
	assert_array(_ended).is_equal([first.id])
	_field.server_spawn("blast", Vector3.ZERO)
	assert_array(_ended).is_equal([first.id, second.id])


func test_a_plume_ends_after_its_lifetime() -> void:
	var v := _field.server_spawn("blast", Vector3.ZERO)
	_field.advance(v.lifetime * 0.5)
	assert_int(_field.volumes.size()).is_equal(1)
	_field.advance(v.lifetime)
	assert_int(_field.volumes.size()).is_equal(0)
	assert_array(_ended).is_equal([v.id])


func test_thick_smoke_blocks_sight_and_thin_smoke_does_not() -> void:
	var v := _field.server_spawn("blast", Vector3(0, 1, -5))
	_field.advance(v.grow)
	assert_bool(_field.sight_blocked(Vector3(0, 1, 0), Vector3(0, 1, -10))).is_true()
	# Well beside it.
	assert_bool(_field.sight_blocked(Vector3(20, 1, 0), Vector3(20, 1, -10))).is_false()
	# Nearly faded.
	_field.advance(v.lifetime - v.grow - 0.2)
	assert_bool(_field.sight_blocked(Vector3(0, 1, 0), Vector3(0, 1, -10))).is_false()


func test_a_soldier_loses_sight_of_a_player_behind_smoke_until_it_thins() -> void:
	if not (ResourceLoader.exists(ENEMIES) and ResourceLoader.exists(WEAPONS) and ResourceLoader.exists(PLAYER)):
		return
	var ground: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	add_child(ground)
	add_child(auto_free((load(WEAPONS) as GDScript).new()))
	var enemies: Node = auto_free((load(ENEMIES) as GDScript).new())
	add_child(enemies)
	# Untyped: the enemies and player modules may be deleted, and their classes with them.
	var player: Node3D = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", 1)
	player.add_to_group(&"players")
	add_child(player)
	player.global_position = Vector3(0, 0.1, -12)
	var squad: Array[Node] = enemies.call(&"server_spawn_squad", 1, Vector3.ZERO)
	await get_tree().process_frame
	var enemy := squad[0] as Node3D
	enemy.global_position = Vector3(0, 0.1, 0)
	for i in 2:
		await get_tree().physics_frame
	var brain := enemy.get_node("Brain")
	assert_bool(brain.call(&"clear_shot", player)).is_true()
	var v := _field.server_spawn("blast", Vector3(0, 1.3, -6))
	_field.advance(v.grow)
	assert_bool(brain.call(&"clear_shot", player)).is_false()
	_field.advance(v.lifetime)
	assert_bool(brain.call(&"clear_shot", player)).is_true()

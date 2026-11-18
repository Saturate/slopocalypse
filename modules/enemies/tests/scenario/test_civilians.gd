extends GdUnitTestSuite
## Civilians: unarmed, their own side (soldiers don't count or fight them), alarmed by
## shooting into running for a refuge away from it, and a death names its source.

const ENEMIES := "res://modules/enemies/enemies_module.gd"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const PLAYER := "res://modules/player/scenes/player.tscn"

var _enemies: Node


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


func _civilian(at := Vector3.ZERO, refuges: Array = []) -> PlayerController:
	var c: PlayerController = _enemies.call(&"server_spawn_civilian", at, 0.0, refuges)
	await get_tree().process_frame
	return c


func test_a_civilian_is_unarmed_and_not_a_soldier() -> void:
	var c := await _civilian()
	assert_bool(c.is_in_group(&"civilians")).is_true()
	assert_bool(c.is_in_group(&"enemies")).is_false()
	assert_str(HitscanWeapon.team_of(c)).is_equal("civilians")
	for child in c.get_node("Head/Camera").get_children():
		assert_bool(child is HitscanWeapon).is_false()
	assert_object(c.get_node("Brain")).is_instanceof(CivilianBrain)
	assert_int((_enemies.call(&"enemies") as Array).size()).is_equal(0)


func test_shooting_nearby_sends_them_to_a_refuge_away_from_it() -> void:
	var behind := Vector3(0, 0, 12)
	var c := await _civilian(Vector3.ZERO, [Vector3(0, 0, -12), behind])
	var brain := c.get_node("Brain") as CivilianBrain
	brain.config["freeze_share"] = 0.0
	# Shots from the far side of the first refuge.
	EventBus.publish(&"weapon.fired", {"from": Vector3(0, 0, -30), "to": Vector3(0, 0, -25), "damage": 0.0})
	assert_int(brain.state).is_equal(CivilianBrain.State.FLEE)
	for i in 600:
		await get_tree().physics_frame
		if brain.state == CivilianBrain.State.HIDE:
			break
	assert_int(brain.state).is_equal(CivilianBrain.State.HIDE)
	assert_float(c.global_position.distance_to(behind)).is_less(2.0)


func test_shooting_far_away_does_not_alarm_them() -> void:
	var c := await _civilian()
	var brain := c.get_node("Brain") as CivilianBrain
	EventBus.publish(&"weapon.fired", {"from": Vector3(0, 0, -500), "to": Vector3(0, 0, -490), "damage": 0.0})
	assert_int(brain.state).is_equal(CivilianBrain.State.CALM)


func test_a_civilians_death_names_its_source() -> void:
	var c := await _civilian()
	var shooter: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	shooter.add_to_group(&"players")
	add_child(shooter)
	var got: Array = []
	var listen := func(p: Dictionary) -> void: got.append(p.get("source"))
	EventBus.subscribe(&"civilian.died", listen)
	(c.get_node("Health") as HealthComponent).server_apply_damage(1000.0, shooter)
	EventBus.unsubscribe(&"civilian.died", listen)
	assert_array(got).contains_exactly([shooter])

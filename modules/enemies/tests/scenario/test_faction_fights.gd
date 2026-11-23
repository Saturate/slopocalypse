extends GdUnitTestSuite
## With factions, soldiers of hostile factions fight each other on sight and soldiers of the
## same faction don't; each faction's soldiers wear its kit and its side.

const ENEMIES := "res://modules/enemies/enemies_module.gd"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const FACTIONS := "res://modules/factions/factions_module.gd"

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
	add_child(auto_free((load(FACTIONS) as GDScript).new()))
	add_child(auto_free((load(WEAPONS) as GDScript).new()))
	add_child(auto_free((load(INVENTORY) as GDScript).new()))
	_enemies = auto_free((load(ENEMIES) as GDScript).new())
	add_child(_enemies)
	((_enemies.get(&"config") as Dictionary)["fortitude"] as Dictionary)["start"] = [20, 20]


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## Two guards 15 m apart, facing each other.
func _pair(a: String, b: String) -> Array[PlayerController]:
	var one: PlayerController = _enemies.call(&"server_spawn_guard", Vector3(0, 0, 0), 0.0, [], a)
	var two: PlayerController = _enemies.call(&"server_spawn_guard", Vector3(0, 0, -15), PI, [], b)
	await get_tree().process_frame
	return [one, two]


func test_hostile_factions_shoot_each_other() -> void:
	var pair := await _pair("militia", "regulars")
	await _frames(360)
	var hurt := 0
	for s in pair:
		var h := s.get_node("Health") as HealthComponent
		if h.health < h.max_health or s.get_meta(&"dead", false):
			hurt += 1
	assert_int(hurt).is_greater(0)


func test_the_same_faction_leaves_itself_alone() -> void:
	var pair := await _pair("regulars", "regulars")
	await _frames(360)
	for s in pair:
		var h := s.get_node("Health") as HealthComponent
		assert_float(h.health).is_equal(h.max_health)


func test_soldiers_wear_their_factions_side_and_kit() -> void:
	var pair := await _pair("scavengers", "militia")
	assert_str(HitscanWeapon.team_of(pair[0])).is_equal("scavengers")
	assert_str(HitscanWeapon.team_of(pair[1])).is_equal("militia")
	var brain := pair[0].get_node("Brain") as EnemyBrain
	assert_bool(brain.is_hostile(pair[1])).is_true()


## Seeded squads: as often as its faction's `gunner.squad_chance` says, a squad's last soldier
## carries the machine gun and its brain knows it is the gunner; nobody else is one.
func test_some_squads_bring_a_gunner_who_knows_it() -> void:
	var api := get_tree().get_first_node_in_group(&"factions_api")
	(_enemies.get(&"_rng") as RandomNumberGenerator).seed = 11
	var squads := 0
	var with_gunner := 0
	var expected := 0.0
	for i in 400:
		var plan: Array[Dictionary] = _enemies.call(&"_plan_squad", 3, Vector3.ZERO)
		var faction: Dictionary = api.call(&"info", str(plan[0]["faction"]))
		squads += 1
		expected += float((faction.get("gunner", {}) as Dictionary).get("squad_chance", 0.0))
		for k in plan.size():
			var gunner := bool((load(ENEMIES) as GDScript).call(&"is_gunner", faction, plan[k].get("gear")))
			if gunner:
				with_gunner += 1
				assert_int(k).is_equal(plan.size() - 1)
	# About the chance the factions give, over 400 squads.
	assert_float(float(with_gunner)).is_between(expected * 0.7, expected * 1.3)
	# A real squad with a gunner: only that soldier's brain is the gunner.
	var squad: Array[Node] = []
	for i in 50:
		squad = _enemies.call(&"server_spawn_squad", 3, Vector3(0, 0, 0))
		await get_tree().process_frame
		var found := squad.any(func(s: Node) -> bool: return (s.get_node("Brain") as EnemyBrain).gunner)
		if found:
			break
		for s in squad:
			s.queue_free()
	var gunners := squad.filter(func(s: Node) -> bool: return (s.get_node("Brain") as EnemyBrain).gunner)
	assert_int(gunners.size()).is_equal(1)
	assert_object(gunners[0]).is_same(squad[-1])

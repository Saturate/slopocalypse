extends GdUnitTestSuite
## Soldiers choose targets by each player's own standing: one squad, two players, one it is
## hostile to and one it lets pass. Killing a soldier moves the killer's standing.

const ENEMIES := "res://modules/enemies/enemies_module.gd"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const FACTIONS := "res://modules/factions/factions_module.gd"
const PLAYER := "res://modules/player/scenes/player.tscn"

var _enemies: Node
var _factions: Node


func before_test() -> void:
	_factions = auto_free((load(FACTIONS) as GDScript).new())
	add_child(_factions)
	add_child(auto_free((load(WEAPONS) as GDScript).new()))
	add_child(auto_free((load(INVENTORY) as GDScript).new()))
	_enemies = auto_free((load(ENEMIES) as GDScript).new())
	add_child(_enemies)


func _player(peer: int) -> PlayerController:
	var p: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	p.set_meta(&"peer_id", peer)
	p.add_to_group(&"players")
	add_child(p)
	return p


func test_the_same_soldier_shoots_one_player_and_lets_another_pass() -> void:
	var soldier: PlayerController = _enemies.call(&"server_spawn_guard", Vector3.ZERO, 0.0, [], "regulars")
	var foe := _player(41)
	var friend := _player(42)
	_factions.call(&"server_set_standing", 42, {"regulars": 50.0})
	var brain := soldier.get_node("Brain") as EnemyBrain
	assert_bool(brain.is_hostile(foe)).is_true()
	assert_bool(brain.is_hostile(friend)).is_false()


func test_killing_a_soldier_moves_the_killers_standing() -> void:
	var soldier: PlayerController = _enemies.call(&"server_spawn_guard", Vector3.ZERO, 0.0, [], "militia")
	var killer := _player(43)
	var before: Dictionary = _factions.call(&"server_standing_of", 43)
	EventBus.publish(&"enemy.died", {"enemy": soldier, "source": killer, "position": Vector3.ZERO})
	var after: Dictionary = _factions.call(&"server_standing_of", 43)
	assert_float(float(after["militia"])).is_less(float(before["militia"]))
	# Regulars and scavengers are hostile to the militia: killing militia pleases them.
	assert_float(float(after["regulars"])).is_greater(float(before["regulars"]))


func test_hurting_a_soldier_costs_a_little_standing() -> void:
	var soldier: PlayerController = _enemies.call(&"server_spawn_guard", Vector3.ZERO, 0.0, [], "scavengers")
	var shooter := _player(44)
	var before: Dictionary = _factions.call(&"server_standing_of", 44)
	(soldier.get_node("Health") as HealthComponent).server_apply_damage(5.0, shooter)
	var after: Dictionary = _factions.call(&"server_standing_of", 44)
	assert_float(float(after["scavengers"])).is_less(float(before["scavengers"]))

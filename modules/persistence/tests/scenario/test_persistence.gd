extends GdUnitTestSuite
## A player who leaves and comes back finds their backpack, guns, health and spot as they
## left them; the world keeps its loot and crate state. Runs on an in-memory save.

const PLAYER := "res://modules/player/scenes/player.tscn"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const PERSISTENCE := "res://modules/persistence/persistence_module.gd"

var _inventory: Node
var _weapons: Node
var _saves: Node


func before_test() -> void:
	_inventory = auto_free((load(INVENTORY) as GDScript).new())
	add_child(_inventory)
	_weapons = auto_free((load(WEAPONS) as GDScript).new())
	add_child(_weapons)
	_saves = auto_free((load(PERSISTENCE) as GDScript).new())
	_saves.set(&"enabled", false)
	add_child(_saves)
	assert_bool(_saves.call(&"start", ":memory:")).is_true()


func _spawn(peer: int, at: Vector3 = Vector3.ZERO) -> PlayerController:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", peer)
	player.add_to_group(&"players")
	add_child(player)
	# Nothing to stand on here; keep them where they are put.
	player.set_physics_process(false)
	player.global_position = at
	EventBus.publish(&"player.spawned", {"player": player, "local": false})
	return player


## What Net and the player module do when a peer drops.
func _leave(peer: int, player: PlayerController) -> void:
	_saves.call(&"_on_peer_leaving", peer)
	_inventory.call(&"_on_peer_left", peer)
	remove_child(player)


func test_a_returning_player_gets_their_gear_and_spot_back() -> void:
	var first := _spawn(61, Vector3(12.0, 3.0, -7.0))
	assert_bool(_saves.call(&"server_admit", 61, "Ranger", "key-a")).is_true()
	assert_bool(_inventory.call(&"server_give", 61, "medkit")).is_true()
	var kits: int = _inventory.call(&"count", 61, "medkit")
	(first.get_node("Health") as HealthComponent).server_apply_damage(35.0)
	_weapons.call(&"server_restore_builds", 61, {"secondary": GunAssembly.build("pistol_tactical")})
	_leave(61, first)

	var again := _spawn(62)
	assert_bool(_saves.call(&"server_admit", 62, "ranger", "key-a")).is_true()
	assert_int(_inventory.call(&"count", 62, "medkit")).is_equal(kits)
	assert_float((again.get_node("Health") as HealthComponent).health).is_equal_approx(65.0, 0.01)
	assert_vector(again.global_position).is_equal_approx(Vector3(12.0, 3.2, -7.0), Vector3.ONE * 0.01)
	assert_dict(_weapons.call(&"build_of", 62, "secondary")).is_equal(GunAssembly.build("pistol_tactical"))


func test_someone_elses_name_is_refused() -> void:
	_spawn(63)
	assert_bool(_saves.call(&"server_admit", 63, "Ranger", "key-a")).is_true()
	_spawn(64)
	assert_bool(_saves.call(&"server_admit", 64, "Ranger", "key-b")).is_false()


func test_the_same_name_cannot_play_twice_at_once() -> void:
	_spawn(65)
	assert_bool(_saves.call(&"server_admit", 65, "Ranger", "key-a")).is_true()
	_spawn(66)
	assert_bool(_saves.call(&"server_admit", 66, "RANGER", "key-a")).is_false()


func test_a_bad_name_is_refused() -> void:
	_spawn(67)
	assert_bool(_saves.call(&"server_admit", 67, "   ", "key-a")).is_false()


func test_dying_then_leaving_starts_over_at_the_spawn_with_an_empty_backpack() -> void:
	var first := _spawn(68, Vector3(40.0, 2.0, 40.0))
	assert_bool(_saves.call(&"server_admit", 68, "Ranger", "key-a")).is_true()
	(first.get_node("Health") as HealthComponent).server_apply_damage(1000.0)
	EventBus.publish(&"player.died", {"player": first, "position": first.global_position})
	first.set_meta(&"dead", true)
	_leave(68, first)

	var again := _spawn(69)
	assert_bool(_saves.call(&"server_admit", 69, "Ranger", "key-a")).is_true()
	assert_array(_inventory.call(&"server_items_of", 69)).is_empty()
	assert_vector(again.global_position).is_equal(Vector3.ZERO)
	assert_float((again.get_node("Health") as HealthComponent).health).is_equal(100.0)


func test_the_world_keeps_its_loot_and_emptied_crates() -> void:
	var player := _spawn(70)
	var crate: LootCrate = _inventory.call(&"server_spawn_crate", Vector3(0, 0, -1.5))
	_inventory.call(&"server_spawn_loot", "medkit", Vector3(3.0, 0.0, 4.0))
	await get_tree().process_frame
	_inventory.call(&"server_search", 70, crate)
	assert_bool(crate.get_meta(&"empty", false)).is_true()
	assert_bool(_saves.call(&"server_save_world")).is_true()

	# The next session lays out fresh loot and full crates before the save is loaded.
	for node: Node in get_tree().get_nodes_in_group(&"loot"):
		node.queue_free()
	_inventory.call(&"server_spawn_loot", "mag_30", Vector3(9.0, 0.0, 9.0))
	_inventory.call(&"server_restore_world", {"loot": [], "crates": [{"index": 0, "items": ["medkit"], "refill_seconds": -1.0}]})
	await get_tree().process_frame
	assert_bool(crate.get_meta(&"empty", false)).is_false()

	_saves.call(&"server_load_world")
	await get_tree().process_frame
	var loot := get_tree().get_nodes_in_group(&"loot").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	assert_int(loot.size()).is_equal(1)
	assert_str((loot[0] as LootItem).item).is_equal("medkit")
	assert_vector((loot[0] as LootItem).global_position).is_equal_approx(Vector3(3.0, 0.0, 4.0), Vector3.ONE * 0.01)
	assert_bool(crate.get_meta(&"empty", false)).is_true()
	assert_array(_inventory.call(&"crate_contents", crate)).is_empty()
	remove_child(player)

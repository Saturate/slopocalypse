extends GdUnitTestSuite
## Guns are items: the gun in your primary or secondary gear slot is the one you hold, with
## the build stored on it; take it out and that hand is empty; a dropped or looted gun keeps
## its parts.

const PLAYER := "res://modules/player/scenes/player.tscn"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const WEAPONS := "res://modules/weapons/weapons_module.gd"

var _inventory: Node
var _weapons: Node


func before_test() -> void:
	_inventory = auto_free((load(INVENTORY) as GDScript).new())
	add_child(_inventory)
	_weapons = auto_free((load(WEAPONS) as GDScript).new())
	add_child(_weapons)


func _spawn(peer: int) -> PlayerController:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", peer)
	player.add_to_group(&"players")
	add_child(player)
	player.set_physics_process(false)
	EventBus.publish(&"player.spawned", {"player": player, "local": false})
	return player


func _gun(player: PlayerController, slot: String) -> HitscanWeapon:
	return player.get_node("Head/Camera").get_node_or_null("Weapon_" + slot) as HitscanWeapon


func test_a_new_player_carries_a_rifle_and_a_pistol_as_items() -> void:
	var player := _spawn(91)
	assert_str(str((_inventory.call(&"slot_item", 91, "primary") as Dictionary).get("item", ""))).is_equal("gun_rifle")
	assert_str(str((_inventory.call(&"slot_item", 91, "secondary") as Dictionary).get("item", ""))).is_equal("gun_pistol")
	assert_object(_gun(player, "primary")).is_not_null()
	assert_object(_gun(player, "secondary")).is_not_null()


func test_taking_the_rifle_out_of_its_slot_empties_that_hand() -> void:
	var player := _spawn(92)
	var gear: InventoryGear = _inventory.call(&"grid_of", 92)
	var rifle := int((_inventory.call(&"slot_item", 92, "primary") as Dictionary)["uid"])
	for placed: Dictionary in gear.items("backpack"):
		gear.remove(int(placed["uid"]))
	assert_bool(_inventory.call(&"server_move", 92, rifle, {"grid": "backpack", "x": 0, "y": 0})).is_true()
	await get_tree().process_frame
	assert_object(_gun(player, "primary")).is_null()
	assert_dict(_weapons.call(&"build_of", 92, "primary")).is_empty()
	# Back in the slot, back in the hands.
	assert_bool(_inventory.call(&"server_move", 92, rifle, {"slot": "primary"})).is_true()
	assert_object(_gun(player, "primary")).is_not_null()


func test_the_build_lives_on_the_gun() -> void:
	var player := _spawn(93)
	var tactical := GunAssembly.build("pistol_tactical")
	assert_bool(_inventory.call(&"server_set_slot_data", 93, "secondary", {"build": tactical})).is_true()
	assert_dict(_weapons.call(&"build_of", 93, "secondary")).is_equal(tactical)
	assert_dict(_gun(player, "secondary").get_meta(&"build")).is_equal(tactical)


func test_a_dropped_gun_keeps_its_parts_for_whoever_picks_it_up() -> void:
	var first := _spawn(94)
	first.global_position = Vector3(0, 0, 0)
	var tactical := GunAssembly.build("pistol_tactical")
	_inventory.call(&"server_set_slot_data", 94, "secondary", {"build": tactical})
	var pistol := int((_inventory.call(&"slot_item", 94, "secondary") as Dictionary)["uid"])
	assert_bool(_inventory.call(&"server_drop", 94, pistol)).is_true()
	await get_tree().process_frame
	var loot := get_tree().get_nodes_in_group(&"loot").filter(func(n: Node) -> bool: return (n as LootItem).item == "gun_pistol")[0] as LootItem
	assert_dict((loot.get_meta(&"data", {}) as Dictionary).get("build", {})).is_equal(tactical)
	# Someone with an empty sidearm slot picks it up: it goes straight into the slot.
	_spawn(95)
	var theirs := int((_inventory.call(&"slot_item", 95, "secondary") as Dictionary)["uid"])
	_inventory.call(&"server_take_uid", 95, theirs)
	assert_bool(_inventory.call(&"server_give", 95, "gun_pistol", loot.get_meta(&"data", {}))).is_true()
	assert_dict(_weapons.call(&"build_of", 95, "secondary")).is_equal(tactical)


func test_the_modding_screen_change_is_stored_on_the_gun() -> void:
	_spawn(96)
	var build: Dictionary = (_weapons.call(&"build_of", 96, "primary") as Dictionary).duplicate()
	# Swap the optic for the 4x scope from the starting kit.
	build["optic"] = "opt_scope_4x"
	assert_bool(_weapons.call(&"server_set_build", 96, build)).is_true()
	var stored: Dictionary = (_inventory.call(&"slot_item", 96, "primary") as Dictionary)["data"]
	assert_str(str((stored["build"] as Dictionary)["optic"])).is_equal("opt_scope_4x")

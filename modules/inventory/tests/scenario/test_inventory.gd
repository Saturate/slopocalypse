extends GdUnitTestSuite
## The server holds each player's gear: a worn rig and pack with a starting kit, moves
## checked by the gear rules, items given and taken by other modules.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/inventory/inventory_module.gd"

var _module: Node


func before_test() -> void:
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)


func _spawn(peer: int) -> void:
	var player: Node = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", peer)
	add_child(player)
	EventBus.publish(&"player.spawned", {"player": player, "local": false})


func test_a_new_player_starts_with_the_kit() -> void:
	_spawn(5)
	assert_int(_module.call(&"count", 5, "opt_scope_4x")).is_equal(1)
	assert_int(_module.call(&"count", 5, "mag_ar_45")).is_equal(1)


func test_a_new_player_wears_a_rig_and_a_pack() -> void:
	_spawn(9)
	var gear: InventoryGear = _module.call(&"grid_of", 9)
	assert_array(Array(gear.grid_names())).contains_exactly(["pockets", "rig", "backpack"])


func test_moves_follow_the_gear_rules() -> void:
	_spawn(6)
	var gear: InventoryGear = _module.call(&"grid_of", 6)
	var in_pack: Array = gear.items("backpack")
	var first: Dictionary = in_pack[0]
	var second: Dictionary = in_pack[1]
	# Onto another item: refused, nothing moves.
	assert_bool(_module.call(&"server_move", 6, int(first["uid"]), {"grid": "backpack", "x": int(second["x"]), "y": int(second["y"])})).is_false()
	var still: Array = gear.items("backpack").filter(func(i: Dictionary) -> bool: return int(i["uid"]) == int(first["uid"]))
	assert_int(int(still[0]["x"])).is_equal(int(first["x"]))
	# A part is not a rig: the rig slot refuses it.
	assert_bool(_module.call(&"server_move", 6, int(first["uid"]), {"slot": "rig"})).is_false()
	# Into the empty bottom right corner: fine.
	var size := gear.grid_size("backpack")
	var corner := {"grid": "backpack", "x": size.x - int(first["w"]), "y": size.y - int(first["h"]), "rotated": bool(first["rotated"])}
	if gear.can_place(str(first["item"]), false, corner, int(first["uid"])):
		assert_bool(_module.call(&"server_move", 6, int(first["uid"]), corner)).is_true()


func test_a_worn_pack_with_things_in_it_cannot_be_dropped() -> void:
	_spawn(10)
	var gear: InventoryGear = _module.call(&"grid_of", 10)
	var pack: Dictionary = gear.all_items().filter(func(i: Dictionary) -> bool: return i.get("slot", "") == "backpack")[0]
	assert_bool(_module.call(&"server_drop", 10, int(pack["uid"]))).is_false()
	assert_int(_module.call(&"count", 10, "bag_small")).is_equal(1)


func test_giving_and_taking_change_the_count() -> void:
	_spawn(7)
	assert_bool(_module.call(&"server_give", 7, "grp_ar_std")).is_true()
	assert_int(_module.call(&"count", 7, "grp_ar_std")).is_equal(1)
	assert_bool(_module.call(&"server_take", 7, "grp_ar_std")).is_true()
	assert_bool(_module.call(&"server_take", 7, "grp_ar_std")).is_false()
	assert_bool(_module.call(&"server_give", 7, "no_such_item")).is_false()


func test_a_full_backpack_refuses_more() -> void:
	_spawn(8)
	var given := 0
	while _module.call(&"server_give", 8, "hg_ar_long") and given < 100:
		given += 1
	assert_int(given).is_less(100)
	assert_bool(_module.call(&"server_give", 8, "hg_ar_long")).is_false()

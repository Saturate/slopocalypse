extends GdUnitTestSuite
## The server holds each player's inventory: a starting kit, moves checked by the grid
## rules, items given and taken by other modules.

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


func test_moves_follow_the_grid_rules() -> void:
	_spawn(6)
	var grid: InventoryGrid = _module.call(&"grid_of", 6)
	var first: Dictionary = grid.items()[0]
	var second: Dictionary = grid.items()[1]
	# Onto another item: refused, nothing moves.
	assert_bool(_module.call(&"server_move", 6, int(first["uid"]), int(second["x"]), int(second["y"]), false)).is_false()
	assert_int(int(grid.items()[0]["x"])).is_equal(int(first["x"]))
	# Into the empty bottom right corner: fine.
	var size: Vector2i = _module.call(&"grid_size")
	assert_bool(_module.call(&"server_move", 6, int(first["uid"]), size.x - int(first["w"]), size.y - int(first["h"]), false)).is_true()


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

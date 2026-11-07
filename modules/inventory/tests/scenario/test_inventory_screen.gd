extends GdUnitTestSuite
## Dragging in the inventory screen asks the server to move the item.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/inventory/inventory_module.gd"

var _module: Node
var _screen: InventoryScreen


func before_test() -> void:
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)
	var player: Node = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", 1)
	add_child(player)
	EventBus.publish(&"player.spawned", {"player": player, "local": false})
	_screen = auto_free(InventoryScreen.new())
	_screen.inventory = _module
	_screen.peer = 1
	add_child(_screen)
	_screen.open()


func after_test() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_dragging_a_tile_moves_the_item() -> void:
	var grid: InventoryGrid = _module.call(&"grid_of", 1)
	var item: Dictionary = grid.items()[0]
	var size: Vector2i = _module.call(&"grid_size")
	var target := Vector2i(size.x - int(item["w"]), size.y - int(item["h"]))
	assert_bool(_screen.pick(Vector2i(int(item["x"]), int(item["y"])))).is_true()
	_screen.drop(target)
	assert_dict(_screen.item_at(target)).contains_keys(["uid"])
	assert_int(int(_screen.item_at(target)["uid"])).is_equal(int(item["uid"]))


func test_an_empty_cell_picks_nothing() -> void:
	var size: Vector2i = _module.call(&"grid_size")
	assert_bool(_screen.pick(size - Vector2i.ONE)).is_false()

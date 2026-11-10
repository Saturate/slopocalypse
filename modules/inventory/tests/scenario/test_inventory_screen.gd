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
	var gear: InventoryGear = _module.call(&"grid_of", 1)
	var item: Dictionary = gear.items("backpack")[0]
	var size := gear.grid_size("backpack")
	var target := {"grid": "backpack", "x": size.x - int(item["w"]), "y": size.y - int(item["h"])}
	assert_bool(_screen.pick(false, {"grid": "backpack", "x": int(item["x"]), "y": int(item["y"])})).is_true()
	_screen.drop_on(false, target)
	assert_int(int(_screen.item_at(false, target).get("uid", -1))).is_equal(int(item["uid"]))


func test_dragging_into_pockets_moves_it_between_grids() -> void:
	var gear: InventoryGear = _module.call(&"grid_of", 1)
	for placed: Dictionary in gear.items("pockets"):
		gear.remove(int(placed["uid"]))
	var item: Dictionary = gear.items("rig")[0]
	assert_bool(_screen.pick(false, {"grid": "rig", "x": int(item["x"]), "y": int(item["y"])})).is_true()
	_screen.drop_on(false, {"grid": "pockets", "x": 0, "y": 0})
	assert_int(int(_screen.item_at(false, {"grid": "pockets", "x": 0, "y": 0}).get("uid", -1))).is_equal(int(item["uid"]))


func test_an_empty_cell_picks_nothing() -> void:
	var gear: InventoryGear = _module.call(&"grid_of", 1)
	for placed: Dictionary in gear.items("pockets"):
		gear.remove(int(placed["uid"]))
	assert_bool(_screen.pick(false, {"grid": "pockets", "x": 3, "y": 0})).is_false()

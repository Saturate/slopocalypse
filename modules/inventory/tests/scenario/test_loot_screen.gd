extends GdUnitTestSuite
## The loot screen turns drags, Ctrl+clicks and drops into requests to the server.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/inventory/inventory_module.gd"

var _module: Node
var _screen: LootScreen
var _body: LootBody


func before_test() -> void:
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)
	var me := _spawn(1, Vector3.ZERO)
	assert_object(me).is_not_null()
	_screen = auto_free(LootScreen.new())
	_screen.inventory = _module
	_screen.peer = 1
	add_child(_screen)
	var victim := _spawn(120, Vector3(0, 0, -1.5))
	EventBus.publish(&"player.died", {"player": victim, "position": victim.global_position})
	victim.set_meta(&"dead", true)
	await get_tree().process_frame
	_body = get_tree().get_nodes_in_group(&"loot_bodies")[-1]
	assert_bool(_module.call(&"server_open", 1, _body)).is_true()


func after_test() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _spawn(peer: int, at: Vector3) -> PlayerController:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", peer)
	player.add_to_group(&"players")
	add_child(player)
	player.global_position = at
	EventBus.publish(&"player.spawned", {"player": player, "local": false})
	return player


func _theirs() -> InventoryGrid:
	return _module.call(&"loot_grid")


func _mine() -> InventoryGrid:
	return _module.call(&"grid_of", 1)


## A free top-left cell in `grid` for `item`, upright.
func _free_cell(grid: InventoryGrid, item: String) -> Vector2i:
	for y in grid.height():
		for x in grid.width():
			if grid.can_place(item, x, y, false, -1):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_opening_a_body_shows_the_screen() -> void:
	assert_bool(_screen.is_open()).is_true()
	assert_object(_theirs()).is_not_null()


func test_dragging_from_the_body_into_the_backpack_takes_it() -> void:
	# Make room first: the starting kit may fill the backpack.
	var mine := _mine()
	for placed: Dictionary in mine.items():
		mine.remove(int(placed["uid"]))
	var item: Dictionary = _theirs().items()[0]
	assert_bool(_screen.pick(true, Vector2i(int(item["x"]), int(item["y"])))).is_true()
	var target := _free_cell(mine, str(item["item"]))
	_screen.drop_on(false, target)
	assert_int(int(_screen.item_at(false, target).get("uid", -1))).is_equal(int(item["uid"]))


func test_ctrl_click_sends_an_item_to_the_other_side() -> void:
	var mine := _mine()
	for placed: Dictionary in mine.items():
		mine.remove(int(placed["uid"]))
	var item: Dictionary = _theirs().items()[0]
	assert_bool(_screen.quick_move(true, Vector2i(int(item["x"]), int(item["y"])))).is_true()
	assert_bool(mine.items().any(func(p: Dictionary) -> bool: return int(p["uid"]) == int(item["uid"]))).is_true()


func test_ctrl_click_with_no_room_asks_nothing() -> void:
	# Fill the body to the brim so nothing from the backpack fits.
	var theirs := _theirs()
	var uid := 900000
	while theirs.insert(uid, "medkit")["ok"]:
		uid += 1
	var mine: Dictionary = _mine().items()[0]
	assert_bool(_screen.quick_move(false, Vector2i(int(mine["x"]), int(mine["y"])))).is_false()


func test_dropping_outside_puts_it_on_the_ground() -> void:
	var item: Dictionary = _theirs().items()[0]
	var loose := get_tree().get_nodes_in_group(&"loot").size()
	assert_bool(_screen.pick(true, Vector2i(int(item["x"]), int(item["y"])))).is_true()
	_screen.drop_outside()
	await get_tree().process_frame
	assert_int(get_tree().get_nodes_in_group(&"loot").size()).is_equal(loose + 1)


func test_closing_ends_the_session() -> void:
	_screen.close()
	assert_bool(_screen.is_open()).is_false()
	assert_object(_theirs()).is_null()

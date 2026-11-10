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
	_spawn(1, Vector3.ZERO)
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


func _theirs() -> InventoryGear:
	return _module.call(&"loot_grid")


func _mine() -> InventoryGear:
	return _module.call(&"grid_of", 1)


## A loose one-cell item on the body (a medkit put there), so it fits the pockets.
func _their_item() -> Dictionary:
	var theirs := _theirs()
	theirs.insert(800000, "medkit")
	return theirs.all_items().filter(func(i: Dictionary) -> bool: return int(i["uid"]) == 800000)[0]


func _place(item: Dictionary, grid: String) -> Dictionary:
	return {"grid": grid, "x": int(item["x"]), "y": int(item["y"])}


func _empty_pockets() -> void:
	for placed: Dictionary in _mine().items("pockets"):
		_mine().remove(int(placed["uid"]))


func test_opening_a_body_shows_the_screen_with_its_slots() -> void:
	assert_bool(_screen.is_open()).is_true()
	assert_int(_theirs().count("rig_light")).is_equal(1)
	assert_dict(_screen.item_at(true, {"slot": "rig"})).contains_keys(["uid"])


func test_dragging_from_the_body_into_your_pockets_takes_it() -> void:
	_empty_pockets()
	var item := _their_item()
	assert_bool(_screen.pick(true, _place(item, str(item["grid"])))).is_true()
	_screen.drop_on(false, {"grid": "pockets", "x": 0, "y": 0})
	assert_int(int(_screen.item_at(false, {"grid": "pockets", "x": 0, "y": 0}).get("uid", -1))).is_equal(int(item["uid"]))


func test_ctrl_click_sends_an_item_to_the_other_side() -> void:
	_empty_pockets()
	var item := _their_item()
	assert_bool(_screen.quick_move(true, _place(item, str(item["grid"])))).is_true()
	assert_bool(_mine().all_items().any(func(p: Dictionary) -> bool: return int(p["uid"]) == int(item["uid"]))).is_true()


func test_ctrl_click_with_no_room_asks_nothing() -> void:
	# Fill every grid on the body so nothing from your gear fits.
	var theirs := _theirs()
	var uid := 900000
	while theirs.insert(uid, "medkit")["ok"]:
		uid += 1
	var mine: Dictionary = _mine().items("backpack")[0]
	assert_bool(_screen.quick_move(false, _place(mine, "backpack"))).is_false()


func test_dropping_outside_puts_it_on_the_ground() -> void:
	var item := _their_item()
	var loose := get_tree().get_nodes_in_group(&"loot").size()
	assert_bool(_screen.pick(true, _place(item, str(item["grid"])))).is_true()
	_screen.drop_outside()
	await get_tree().process_frame
	assert_int(get_tree().get_nodes_in_group(&"loot").size()).is_equal(loose + 1)


func test_closing_ends_the_session() -> void:
	_screen.close()
	assert_bool(_screen.is_open()).is_false()
	assert_object(_theirs()).is_null()

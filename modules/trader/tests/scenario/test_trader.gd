extends GdUnitTestSuite
## The trader: buying takes tokens and puts the item in your gear if it fits, selling pays a
## share, and nothing trades from away from the stall.

const PLAYER := "res://modules/player/scenes/player.tscn"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const MISSIONS := "res://modules/missions/missions_module.gd"
const TRADER := "res://modules/trader/trader_module.gd"
const SPAWN := Vector3(0.0, 1.0, 0.0)

var _inventory: Node
var _missions: Node
var _trader: Node
var _player: PlayerController


func before_test() -> void:
	_inventory = auto_free((load(INVENTORY) as GDScript).new())
	add_child(_inventory)
	_missions = auto_free((load(MISSIONS) as GDScript).new())
	add_child(_missions)
	_trader = auto_free((load(TRADER) as GDScript).new())
	add_child(_trader)
	EventBus.publish(&"world.ready", {"spawn": SPAWN})
	_player = auto_free((load(PLAYER) as PackedScene).instantiate())
	_player.set_meta(&"peer_id", 81)
	_player.add_to_group(&"players")
	add_child(_player)
	_player.set_physics_process(false)
	EventBus.publish(&"player.spawned", {"player": _player, "local": false})
	# At the counter.
	var stall := _trader.get_node("TraderStall") as Node3D
	_player.global_position = stall.global_position + Vector3(-1.2, 0, 0)


func _tokens() -> int:
	return int(_missions.call(&"server_tokens_of", 81))


func test_buying_takes_tokens_and_gives_the_item() -> void:
	_missions.call(&"server_set_tokens", 81, 100)
	var before := int(_inventory.call(&"count", 81, "medkit"))
	assert_bool(_trader.call(&"server_buy", 81, "medkit")).is_true()
	assert_int(int(_inventory.call(&"count", 81, "medkit"))).is_equal(before + 1)
	assert_int(_tokens()).is_equal(100 - int(_trader.call(&"price_of", "medkit")))


func test_no_tokens_no_sale() -> void:
	_missions.call(&"server_set_tokens", 81, 0)
	var before := int(_inventory.call(&"count", 81, "medkit"))
	assert_bool(_trader.call(&"server_buy", 81, "medkit")).is_false()
	assert_int(int(_inventory.call(&"count", 81, "medkit"))).is_equal(before)


func test_only_what_is_in_stock() -> void:
	_missions.call(&"server_set_tokens", 81, 1000)
	assert_bool(_trader.call(&"server_buy", 81, "usb_drive")).is_false()
	assert_int(_tokens()).is_equal(1000)


func test_no_room_keeps_the_tokens() -> void:
	_missions.call(&"server_set_tokens", 81, 100000)
	while _inventory.call(&"server_give", 81, "medkit"):
		pass
	var tokens := _tokens()
	assert_bool(_trader.call(&"server_buy", 81, "bag_large")).is_false()
	assert_int(_tokens()).is_equal(tokens)


func test_selling_pays_a_share_and_takes_the_item() -> void:
	_missions.call(&"server_set_tokens", 81, 0)
	var gear: InventoryGear = _inventory.call(&"grid_of", 81)
	var item: Dictionary = gear.all_items().filter(func(i: Dictionary) -> bool: return i.has("grid"))[0]
	var before := int(_inventory.call(&"count", 81, str(item["item"])))
	assert_bool(_trader.call(&"server_sell", 81, int(item["uid"]))).is_true()
	assert_int(int(_inventory.call(&"count", 81, str(item["item"])))).is_equal(before - 1)
	assert_int(_tokens()).is_equal(int(_trader.call(&"sell_price", str(item["item"]))))
	assert_int(int(_trader.call(&"sell_price", str(item["item"])))).is_less_equal(int(_trader.call(&"price_of", str(item["item"]))))


func test_nothing_trades_away_from_the_stall() -> void:
	_missions.call(&"server_set_tokens", 81, 100)
	_player.global_position = SPAWN + Vector3(0, 0, -60)
	assert_bool(_trader.call(&"server_buy", 81, "medkit")).is_false()
	var gear: InventoryGear = _inventory.call(&"grid_of", 81)
	assert_bool(_trader.call(&"server_sell", 81, int(gear.all_items()[0]["uid"]))).is_false()
	assert_int(_tokens()).is_equal(100)


func test_f_at_the_stall_opens_the_trade_screen() -> void:
	var stall := _trader.get_node("TraderStall") as Node3D
	_player.look_at(Vector3(stall.global_position.x, _player.global_position.y, stall.global_position.z), Vector3.UP)
	var opened := []
	var on_open := func(p: Dictionary) -> void: opened.append(p)
	EventBus.subscribe(&"trader.opened", on_open)
	var payload := {"player": _player}
	EventBus.publish(&"player.interact", payload)
	EventBus.unsubscribe(&"trader.opened", on_open)
	assert_bool(payload.get("handled", false)).is_true()

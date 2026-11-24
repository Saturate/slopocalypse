extends GdUnitTestSuite
## The trade screen: tabs filter the goods by the item data's category, a good dropped on a
## place in your gear is bought into that place, your item dropped on the goods is sold,
## the details come from the item data, and what you cannot pay for is shown as such and
## not asked for.

const PLAYER := "res://modules/player/scenes/player.tscn"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const MISSIONS := "res://modules/missions/missions_module.gd"
const TRADER := "res://modules/trader/trader_module.gd"
const SPAWN := Vector3(0.0, 1.0, 0.0)
## The local instance is the server in a test (no network peer), so the player is peer 1.
const PEER := 1

var _inventory: Node
var _missions: Node
var _trader: Node
var _player: PlayerController
var _screen: TraderScreen


class HeldTrader extends Node:
	var real: Node
	var asked: Array[String] = []

	func stock() -> Array:
		return real.call(&"stock")

	func tabs() -> Array:
		return real.call(&"tabs")

	func price_of(item: String) -> int:
		return int(real.call(&"price_of", item))

	func sell_price(item: String) -> int:
		return int(real.call(&"sell_price", item))

	func request_buy(item: String) -> void:
		asked.append(item)

	func request_sell(uid: int) -> void:
		real.call(&"request_sell", uid)


func before_test() -> void:
	_inventory = auto_free((load(INVENTORY) as GDScript).new())
	add_child(_inventory)
	_missions = auto_free((load(MISSIONS) as GDScript).new())
	add_child(_missions)
	_trader = auto_free((load(TRADER) as GDScript).new())
	add_child(_trader)
	EventBus.publish(&"world.ready", {"spawn": SPAWN})
	_player = auto_free((load(PLAYER) as PackedScene).instantiate())
	_player.set_meta(&"peer_id", PEER)
	_player.add_to_group(&"players")
	add_child(_player)
	_player.set_physics_process(false)
	EventBus.publish(&"player.spawned", {"player": _player, "local": false})
	var stall := _trader.get_node("TraderStall") as Node3D
	_player.global_position = stall.global_position + Vector3(-1.2, 0, 0)
	_screen = auto_free(TraderScreen.new())
	_screen.trader = _trader
	_screen.peer = PEER
	add_child(_screen)
	_screen.open()


func after_test() -> void:
	_screen.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _gear() -> InventoryGear:
	return _inventory.call(&"grid_of", PEER)


## The last place in the backpack `item` fits, scanning from the bottom right: never the
## first free place the server would pick by itself.
func _last_free(item: String) -> Dictionary:
	var size := _gear().grid_size("backpack")
	for y in range(size.y - 1, -1, -1):
		for x in range(size.x - 1, -1, -1):
			var spot := {"grid": "backpack", "x": x, "y": y, "rotated": false}
			if _gear().can_place(item, false, spot, -1):
				return spot
	return {}


## Every place in the backpack `item` fits, row by row.
func _free_spots(item: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var size := _gear().grid_size("backpack")
	for y in size.y:
		for x in size.x:
			var spot := {"grid": "backpack", "x": x, "y": y, "rotated": false}
			if _gear().can_place(item, false, spot, -1):
				out.append(spot)
	return out


## A second screen whose trader holds every buy instead of handing it to the server, so the
## test decides when (and whether) the bought good arrives.
func _held_screen() -> TraderScreen:
	var held_trader: HeldTrader = auto_free(HeldTrader.new())
	held_trader.real = _trader
	add_child(held_trader)
	var screen: TraderScreen = auto_free(TraderScreen.new())
	screen.trader = held_trader
	screen.peer = PEER
	add_child(screen)
	screen.open()
	return screen


func _placed_at(place: Dictionary) -> Dictionary:
	for placed: Dictionary in _gear().all_items():
		if str(placed.get("grid", "")) == str(place["grid"]) and Rect2i(int(placed["x"]), int(placed["y"]), int(placed["w"]), int(placed["h"])).has_point(Vector2i(int(place["x"]), int(place["y"]))):
			return placed
	return {}


func _uid_at(place: Dictionary) -> int:
	return int(_placed_at(place).get("uid", -1))


func _item_at(place: Dictionary) -> String:
	return str(_placed_at(place).get("item", ""))


func test_tabs_filter_goods_by_item_category() -> void:
	_screen.set_category("all")
	assert_int(_screen.shown_goods().size()).is_equal((_trader.call(&"stock") as Array).size())
	_screen.set_category("guns")
	assert_array(_screen.shown_goods()).contains(["gun_rifle", "gun_pistol", "gun_mg"])
	assert_array(_screen.shown_goods()).not_contains(["medkit", "mag_ar_30"])
	_screen.set_category("ammo")
	# Pistol magazines sit with the pistol parts by kind; their category puts them with ammo.
	assert_array(_screen.shown_goods()).contains(["mag_ar_30", "mag_pistol_15", "belt_mg_100"])
	assert_array(_screen.shown_goods()).not_contains(["gun_rifle"])
	_screen.set_category("medical")
	assert_array(_screen.shown_goods()).contains_exactly(["medkit"])
	_screen.set_category("gear")
	assert_array(_screen.shown_goods()).contains(["opt_reddot", "bag_large", "glowstick", "breach_charge"])
	assert_array(_screen.shown_goods()).not_contains(["medkit", "gun_rifle", "mag_ar_30"])


func test_every_good_is_under_one_tab() -> void:
	var named := 0
	for category: String in ["guns", "ammo", "medical", "gear"]:
		_screen.set_category(category)
		named += _screen.shown_goods().size()
	assert_int(named).is_equal((_trader.call(&"stock") as Array).size())


func test_a_good_dropped_on_a_place_is_bought_into_it() -> void:
	_missions.call(&"server_set_tokens", PEER, 100)
	var place := _last_free("medkit")
	assert_dict(place).is_not_empty()
	var had := int(_inventory.call(&"count", PEER, "medkit"))
	assert_bool(_screen.buy_at("medkit", place)).is_true()
	assert_int(int(_inventory.call(&"count", PEER, "medkit"))).is_equal(had + 1)
	assert_str(_item_at(place)).is_equal("medkit")
	assert_int(int(_missions.call(&"server_tokens_of", PEER))).is_equal(100 - int(_trader.call(&"price_of", "medkit")))


func test_two_goods_bought_before_either_arrives_land_in_their_own_places() -> void:
	_missions.call(&"server_set_tokens", PEER, 100)
	var held := _held_screen()
	var spots := _free_spots("medkit")
	var first: Dictionary = spots[spots.size() - 1]
	var second: Dictionary = spots[spots.size() - 2]
	assert_bool(held.buy_at("medkit", first)).is_true()
	assert_bool(held.buy_at("medkit", second)).is_true()
	assert_int(held.pending_buys()).is_equal(2)
	assert_bool(_inventory.call(&"server_give", PEER, "medkit")).is_true()
	assert_bool(_inventory.call(&"server_give", PEER, "medkit")).is_true()
	assert_int(held.pending_buys()).is_equal(0)
	var at_first := _uid_at(first)
	var at_second := _uid_at(second)
	assert_int(at_first).is_not_equal(-1)
	assert_int(at_second).is_not_equal(-1)
	# The first buy takes the first medkit the server gave.
	assert_int(at_first).is_less(at_second)


func test_a_bought_good_stays_put_when_its_place_was_taken() -> void:
	_missions.call(&"server_set_tokens", PEER, 100)
	var held := _held_screen()
	var place := _last_free("medkit")
	assert_bool(held.buy_at("medkit", place)).is_true()
	# Something else lands on the spot before the bought medkit arrives.
	var small := _gear().all_items().filter(func(i: Dictionary) -> bool: return i.has("grid") and int(i["w"]) == 1 and int(i["h"]) == 1)
	assert_array(small).is_not_empty()
	var filler: Dictionary = small[0]
	assert_str(_gear().move_item(int(filler["uid"]), place)).is_empty()
	assert_bool(_inventory.call(&"server_give", PEER, "medkit")).is_true()
	assert_int(held.pending_buys()).is_equal(0)
	assert_int(_uid_at(place)).is_equal(int(filler["uid"]))


func test_closing_forgets_goods_still_on_their_way() -> void:
	_missions.call(&"server_set_tokens", PEER, 100)
	var held := _held_screen()
	assert_bool(held.buy_at("medkit", _last_free("medkit"))).is_true()
	held.close()
	assert_int(held.pending_buys()).is_equal(0)


func test_a_good_that_never_arrives_is_forgotten() -> void:
	_missions.call(&"server_set_tokens", PEER, 100)
	var held := _held_screen()
	var place := _last_free("medkit")
	assert_bool(held.buy_at("medkit", place)).is_true()
	held._process(TraderScreen.PENDING_SECONDS + 0.1)
	assert_int(held.pending_buys()).is_equal(0)
	# A medkit picked up later stays where it lands.
	assert_bool(_inventory.call(&"server_give", PEER, "medkit")).is_true()
	assert_int(_uid_at(place)).is_equal(-1)


func test_a_good_that_does_not_fit_its_place_is_not_bought() -> void:
	_missions.call(&"server_set_tokens", PEER, 1000)
	var taken: Dictionary = _gear().items("backpack")[0]
	var tokens := int(_missions.call(&"server_tokens_of", PEER))
	assert_bool(_screen.buy_at("bag_large", {"grid": "backpack", "x": int(taken["x"]), "y": int(taken["y"]), "rotated": false})).is_false()
	assert_str(_screen.message()).is_not_empty()
	assert_int(int(_missions.call(&"server_tokens_of", PEER))).is_equal(tokens)


func test_too_few_tokens_is_said_and_not_asked() -> void:
	_missions.call(&"server_set_tokens", PEER, 0)
	var refused := []
	var on_refused := func(p: Dictionary) -> void: refused.append(p)
	EventBus.subscribe(&"trader.refused", on_refused)
	assert_bool(_screen.buy("gun_rifle")).is_false()
	EventBus.unsubscribe(&"trader.refused", on_refused)
	assert_str(_screen.message()).is_not_empty()
	assert_array(refused).is_empty()


func test_no_room_is_said_and_not_asked() -> void:
	_missions.call(&"server_set_tokens", PEER, 100000)
	while _inventory.call(&"server_give", PEER, "medkit"):
		pass
	var tokens := int(_missions.call(&"server_tokens_of", PEER))
	assert_bool(_screen.buy("bag_large")).is_false()
	assert_str(_screen.message()).is_not_empty()
	assert_int(int(_missions.call(&"server_tokens_of", PEER))).is_equal(tokens)


func test_affordability_follows_tokens() -> void:
	var price := int(_trader.call(&"price_of", "gun_mg"))
	_missions.call(&"server_set_tokens", PEER, price - 1)
	assert_bool(_screen.can_afford("gun_mg")).is_false()
	_missions.call(&"server_set_tokens", PEER, price)
	assert_bool(_screen.can_afford("gun_mg")).is_true()


func test_your_item_dropped_on_the_goods_is_sold() -> void:
	_missions.call(&"server_set_tokens", PEER, 0)
	var item: Dictionary = _gear().items("backpack")[0]
	var place := {"grid": "backpack", "x": int(item["x"]), "y": int(item["y"])}
	assert_bool(_screen.pick_mine(place)).is_true()
	assert_bool(_screen.drop_to_sell()).is_true()
	assert_int(_uid_at(place)).is_not_equal(int(item["uid"]))
	assert_int(int(_missions.call(&"server_tokens_of", PEER))).is_equal(int(_trader.call(&"sell_price", str(item["item"]))))


func test_nothing_dragged_sells_nothing() -> void:
	assert_bool(_screen.drop_to_sell()).is_false()


func test_details_come_from_the_item_data() -> void:
	var good := _screen.detail_of("medkit", false)
	var info: Dictionary = _inventory.call(&"item_info", "medkit")
	assert_str(str(good["name"])).is_equal(str(info["name"]))
	assert_str(str(good["about"])).is_equal(str(info["about"]))
	assert_int(int(good["price"])).is_equal(int(_trader.call(&"price_of", "medkit")))
	var labels: Array = (good["stats"] as Array).map(func(r: Dictionary) -> String: return str(r["label"]))
	assert_array(labels).contains(["Heals"])
	var mine := _screen.detail_of("medkit", true)
	assert_int(int(mine["price"])).is_equal(int(_trader.call(&"sell_price", "medkit")))
	assert_bool(bool(mine["selling"])).is_true()


func test_a_pack_shows_what_it_holds() -> void:
	var labels: Array = (_screen.detail_of("bag_small", false)["stats"] as Array).map(func(r: Dictionary) -> String: return str(r["label"]))
	assert_array(labels).contains(["Holds"])


func test_showing_a_detail_keeps_it() -> void:
	_screen.show_detail("gun_rifle", false)
	assert_str(str(_screen.detail()["item"])).is_equal("gun_rifle")
	assert_bool(bool(_screen.detail()["selling"])).is_false()

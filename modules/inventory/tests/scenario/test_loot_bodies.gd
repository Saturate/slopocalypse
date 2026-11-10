extends GdUnitTestSuite
## The dead keep their gear on their body; searching a body or crate opens a loot session
## the server checks: moves need reach, the first request for an item wins, and a move with
## no room changes nothing.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/inventory/inventory_module.gd"

var _module: Node


func before_test() -> void:
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)


func _spawn(peer: int, at: Vector3 = Vector3.ZERO, npc: bool = false) -> PlayerController:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", peer)
	player.add_to_group(&"players")
	add_child(player)
	player.global_position = at
	EventBus.publish(&"player.spawned", {"player": player, "local": false, "npc": npc})
	return player


func _bodies() -> Array:
	return get_tree().get_nodes_in_group(&"loot_bodies").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())


## Kills `victim` and returns the body it leaves, with what it carried.
func _kill(victim: PlayerController) -> LootBody:
	var before := _bodies().size()
	EventBus.publish(&"player.died", {"player": victim, "position": victim.global_position})
	victim.set_meta(&"dead", true)
	await get_tree().process_frame
	assert_int(_bodies().size()).is_equal(before + 1)
	return _bodies()[-1]


func _items(node: Node) -> Array:
	return _module.call(&"crate_contents", node)


func _first_uid(node: Node) -> int:
	var grid: InventoryGrid = (_module.get(&"_containers") as Dictionary)[int(node.get_meta(&"container"))]
	return int(grid.items()[0]["uid"])


func test_a_body_keeps_what_the_dead_carried_and_nothing_scatters() -> void:
	var victim := _spawn(81)
	var carried: Array = []
	for placed: Dictionary in (_module.call(&"grid_of", 81) as InventoryGrid).items():
		carried.append(str(placed["item"]))
	assert_int(carried.size()).is_greater(0)
	var loose := get_tree().get_nodes_in_group(&"loot").size()
	var body := await _kill(victim)
	assert_array(_items(body)).contains_exactly_in_any_order(carried)
	assert_int(get_tree().get_nodes_in_group(&"loot").size()).is_equal(loose)
	# The player comes back with an empty backpack.
	assert_int((_module.call(&"grid_of", 81) as InventoryGrid).items().size()).is_equal(0)


func test_a_soldier_leaves_a_body_too() -> void:
	var soldier := _spawn(-5, Vector3.ZERO, true)
	var body: LootBody
	var before := _bodies().size()
	EventBus.publish(&"enemy.died", {"enemy": soldier, "position": soldier.global_position})
	await get_tree().process_frame
	assert_int(_bodies().size()).is_equal(before + 1)
	body = _bodies()[-1]
	assert_object(body).is_not_null()


func test_searching_a_body_takes_an_item_across() -> void:
	var body := await _kill(_spawn(82, Vector3(0, 0, -1.5)))
	_spawn(83)
	assert_bool(_module.call(&"server_open", 83, body)).is_true()
	var uid := _first_uid(body)
	var count := _items(body).size()
	assert_bool(_module.call(&"server_quick_move", 83, true, uid)).is_true()
	assert_int(_items(body).size()).is_equal(count - 1)
	var mine: InventoryGrid = _module.call(&"grid_of", 83)
	assert_bool(mine.items().any(func(p: Dictionary) -> bool: return int(p["uid"]) == uid)).is_true()


func test_f_on_a_body_opens_it() -> void:
	var body := await _kill(_spawn(84, Vector3(0, 0, -1.2)))
	var looter := _spawn(85)
	var eye := (looter.get_node("Head/Camera") as Node3D).global_position
	var d := body.global_position + Vector3.UP * 0.15 - eye
	(looter.get_node("Head") as Node3D).rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
	var payload := {"player": looter}
	EventBus.publish(&"player.interact", payload)
	assert_bool(payload.get("handled", false)).is_true()
	assert_int(int((_module.get(&"_viewers") as Dictionary).get(85, -1))).is_equal(int(body.get_meta(&"container")))


func test_a_move_from_out_of_reach_is_refused() -> void:
	var body := await _kill(_spawn(86, Vector3(0, 0, -1.5)))
	var looter := _spawn(87)
	assert_bool(_module.call(&"server_open", 87, body)).is_true()
	looter.global_position = Vector3(0, 0, 20)
	var count := _items(body).size()
	assert_bool(_module.call(&"server_quick_move", 87, true, _first_uid(body))).is_false()
	assert_int(_items(body).size()).is_equal(count)
	# Walking off closes the session too.
	assert_bool((_module.get(&"_viewers") as Dictionary).has(87)).is_false()


func test_opening_from_too_far_is_refused() -> void:
	var body := await _kill(_spawn(88, Vector3(0, 0, -30)))
	_spawn(89)
	assert_bool(_module.call(&"server_open", 89, body)).is_false()


func test_two_looters_taking_the_same_item_one_wins() -> void:
	var body := await _kill(_spawn(90, Vector3(0, 0, -1.5)))
	_spawn(91)
	_spawn(92, Vector3(0.5, 0, 0))
	assert_bool(_module.call(&"server_open", 91, body)).is_true()
	assert_bool(_module.call(&"server_open", 92, body)).is_true()
	var uid := _first_uid(body)
	assert_bool(_module.call(&"server_quick_move", 91, true, uid)).is_true()
	assert_bool(_module.call(&"server_quick_move", 92, true, uid)).is_false()


func test_a_move_with_no_room_changes_nothing() -> void:
	var body := await _kill(_spawn(93, Vector3(0, 0, -1.5)))
	_spawn(94)
	assert_bool(_module.call(&"server_open", 94, body)).is_true()
	var uid := _first_uid(body)
	var size: Vector2i = _module.call(&"grid_size")
	# Off the edge of the backpack.
	assert_bool(_module.call(&"server_transfer", 94, true, uid, false, size.x, size.y, false)).is_false()
	assert_int(_first_uid(body)).is_equal(uid)


func test_putting_something_on_a_body_works_both_ways() -> void:
	var body := await _kill(_spawn(95, Vector3(0, 0, -1.5)))
	_spawn(96)
	assert_bool(_module.call(&"server_open", 96, body)).is_true()
	var mine: InventoryGrid = _module.call(&"grid_of", 96)
	var uid := int(mine.items()[0]["uid"])
	var count := _items(body).size()
	assert_bool(_module.call(&"server_quick_move", 96, false, uid)).is_true()
	assert_int(_items(body).size()).is_equal(count + 1)


func test_an_emptied_body_goes_sooner() -> void:
	var body := await _kill(_spawn(97, Vector3(0, 0, -1.5)))
	_spawn(98)
	assert_bool(_module.call(&"server_open", 98, body)).is_true()
	var id := int(body.get_meta(&"container"))
	var left: Dictionary = _module.get(&"_body_left")
	assert_float(float(left[id])).is_greater(60.0)
	_module.call(&"server_take_all", 98)
	assert_array(_items(body)).is_empty()
	assert_float(float(left[id])).is_less_equal(30.0)
	assert_bool(body.get_meta(&"empty", false)).is_true()


func test_a_crate_opens_the_same_way_and_take_all_empties_it() -> void:
	var looter := _spawn(99)
	var crate: LootCrate = _module.call(&"server_spawn_crate", Vector3(0, 0, -1.5))
	await get_tree().process_frame
	var payload := {"player": looter}
	EventBus.publish(&"player.interact", payload)
	assert_bool(payload.get("handled", false)).is_true()
	var inside: Array = _items(crate)
	assert_int(_module.call(&"server_take_all", 99)).is_equal(inside.size())
	assert_array(_items(crate)).is_empty()
	assert_bool(crate.get_meta(&"empty", false)).is_true()


func test_a_saved_world_keeps_a_bodys_gear_as_loot() -> void:
	var body := await _kill(_spawn(100, Vector3(4, 0, 4)))
	var held := _items(body).size()
	var state: Dictionary = _module.call(&"server_world_state")
	var near := (state["loot"] as Array).filter(func(l: Dictionary) -> bool: return (l["position"] as Vector3).distance_to(body.global_position) < 1.0)
	assert_int(near.size()).is_equal(held)

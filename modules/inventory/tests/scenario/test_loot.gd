extends GdUnitTestSuite
## Loot on the ground: F picks up the item in reach if it fits, dropping lays an item from
## the inventory in front of the player, and one press never also enters a car.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/inventory/inventory_module.gd"

var _module: Node


func before_test() -> void:
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)


func _spawn(peer: int) -> PlayerController:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", peer)
	player.add_to_group(&"players")
	add_child(player)
	EventBus.publish(&"player.spawned", {"player": player, "local": false})
	return player


## Tilts the head so the crosshair is on `point`, as a player looks down at an item.
func _look_at(player: PlayerController, point: Vector3) -> void:
	var eye := (player.get_node("Head/Camera") as Node3D).global_position
	var d := point - eye
	(player.get_node("Head") as Node3D).rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _in_front(player: PlayerController, metres: float) -> Vector3:
	return player.global_position - player.global_transform.basis.z * metres


func test_e_picks_up_loot_in_front_and_claims_the_press() -> void:
	var player := _spawn(41)
	var loot: LootItem = _module.call(&"server_spawn_loot", "grp_ar_std", _in_front(player, 1.2))
	await get_tree().process_frame
	_look_at(player, loot.global_position)
	var payload := {"player": player}
	EventBus.publish(&"player.interact", payload)
	assert_bool(payload.get("handled", false)).is_true()
	assert_int(_module.call(&"count", 41, "grp_ar_std")).is_equal(1)
	assert_bool(loot.is_queued_for_deletion()).is_true()


func test_loot_behind_you_or_far_away_stays() -> void:
	var player := _spawn(42)
	_module.call(&"server_spawn_loot", "grp_ar_std", _in_front(player, -1.2))
	_module.call(&"server_spawn_loot", "muz_flash", _in_front(player, 6.0))
	await get_tree().process_frame
	var payload := {"player": player}
	EventBus.publish(&"player.interact", payload)
	assert_bool(payload.get("handled", false)).is_false()
	assert_int(_module.call(&"count", 42, "grp_ar_std")).is_equal(0)


func test_dropping_puts_the_item_on_the_ground() -> void:
	_spawn(43)
	var gear: InventoryGear = _module.call(&"grid_of", 43)
	var first: Dictionary = gear.all_items().filter(func(i: Dictionary) -> bool: return i.has("grid"))[0]
	var before: int = _module.call(&"count", 43, str(first["item"]))
	assert_bool(_module.call(&"server_drop", 43, int(first["uid"]))).is_true()
	await get_tree().process_frame
	assert_int(_module.call(&"count", 43, str(first["item"]))).is_equal(before - 1)
	var dropped := get_tree().get_nodes_in_group(&"loot").filter(func(n: Node) -> bool: return (n as LootItem).item == str(first["item"]))
	assert_int(dropped.size()).is_greater(0)


func test_no_room_leaves_the_loot_where_it_is() -> void:
	var player := _spawn(44)
	while _module.call(&"server_give", 44, "mag_pistol_15"):
		pass
	var loot: LootItem = _module.call(&"server_spawn_loot", "bar_ar_14", _in_front(player, 1.2))
	await get_tree().process_frame
	EventBus.publish(&"player.interact", {"player": player})
	assert_bool(loot.is_queued_for_deletion()).is_false()

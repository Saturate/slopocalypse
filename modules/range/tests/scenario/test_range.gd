extends GdUnitTestSuite
## The test range: with `--range` the first player to arrive rides straight out to a fixed
## row of buildings, one per material, carrying the range's charges; the HUD names the
## material under the crosshair.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MISSIONS := "res://modules/missions/missions_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const RANGE := "res://modules/range/range_module.gd"
const SPAWN := Vector3(0.0, 1.0, 0.0)

var _missions: Node
var _inventory: Node
var _range: Node


func before_test() -> void:
	Net.extra_args = PackedStringArray(["--range"])
	EventBus.subscribe(&"player.move_requested", _on_move)
	_inventory = auto_free((load(INVENTORY) as GDScript).new())
	add_child(_inventory)
	_missions = auto_free((load(MISSIONS) as GDScript).new())
	add_child(_missions)
	_range = auto_free((load(RANGE) as GDScript).new())
	add_child(_range)
	EventBus.publish(&"world.ready", {"spawn": SPAWN})


func after_test() -> void:
	Net.extra_args = PackedStringArray()
	EventBus.unsubscribe(&"player.move_requested", _on_move)


func _on_move(p: Dictionary) -> void:
	(p["player"] as Node3D).global_position = p["position"]


func _arrive(peer: int) -> PlayerController:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", peer)
	player.add_to_group(&"players")
	add_child(player)
	player.set_physics_process(false)
	player.global_position = SPAWN + Vector3(1, 0, 2)
	EventBus.publish(&"player.spawned", {"player": player, "local": false})
	await get_tree().process_frame
	await get_tree().physics_frame
	return player


func test_arriving_rides_out_to_one_building_per_material() -> void:
	var player := await _arrive(71)
	assert_str(str(_missions.get(&"state"))).is_equal("in_mission")
	assert_str(str((_missions.get(&"current") as Dictionary)["type"])).is_equal("test_range")
	var materials: Array = (_missions.get(&"buildings") as Array).map(func(b: Dictionary) -> String: return "%s/%s" % [b["material"], b["glass"]])
	assert_array(materials).contains_exactly(["wood/window_glass", "brick/window_glass", "concrete/window_glass", "wood/security_glass", "concrete/security_glass"])
	assert_float(player.global_position.distance_to(SPAWN)).is_greater(50.0)
	# Set down across the road from the row, within easy reach of every building.
	await get_tree().physics_frame
	for b: Dictionary in _missions.get(&"buildings"):
		assert_float(player.global_position.distance_to(b["position"])).is_less(40.0)


func test_the_range_hands_out_its_charges() -> void:
	await _arrive(72)
	var gifts: Dictionary = (_range.get(&"config") as Dictionary)["gifts"]
	# On top of whatever the starting kit carries.
	assert_int(int(_inventory.call(&"count", 72, "breach_charge"))).is_greater_equal(int(gifts["breach_charge"]))


func test_without_the_flag_it_stays_out_of_the_way() -> void:
	Net.extra_args = PackedStringArray()
	var idle: Node = auto_free((load(RANGE) as GDScript).new())
	add_child(idle)
	assert_bool(bool(idle.get(&"active"))).is_false()

extends GdUnitTestSuite
## The run flow: offers on the board, choosing one for everyone, riding out from home to the
## drop-off and back, and the run ending once nobody is out.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/missions/missions_module.gd"
const SPAWN := Vector3(0.0, 1.0, 0.0)

var _module: Node
var _moves: Array = []


func before_test() -> void:
	_moves = []
	EventBus.subscribe(&"player.move_requested", _on_move)
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)
	EventBus.publish(&"world.ready", {"spawn": SPAWN})


func after_test() -> void:
	EventBus.unsubscribe(&"player.move_requested", _on_move)


## Stands in for the player module: moves the player where asked.
func _on_move(p: Dictionary) -> void:
	_moves.append(p)
	(p["player"] as Node3D).global_position = p["position"]


func _spawn(peer: int, at: Vector3) -> PlayerController:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", peer)
	player.add_to_group(&"players")
	add_child(player)
	player.global_position = at
	return player


func test_the_board_offers_distinct_missions_from_data() -> void:
	var offers: Array = _module.get(&"offers")
	assert_int(offers.size()).is_equal(3)
	var ids := offers.map(func(o: Dictionary) -> String: return str(o["id"]))
	assert_int(ids.size()).is_equal(3)
	assert_bool(ids[0] != ids[1] and ids[1] != ids[2] and ids[0] != ids[2]).is_true()
	for o: Dictionary in offers:
		assert_float(float(o["distance"])).is_greater(0.0)
		assert_float(float(o["payout"])).is_greater(0.0)


func test_offers_have_codenames_and_a_kind_with_its_name() -> void:
	var cfg: Dictionary = _module.get(&"config")
	for seed_value in 10:
		for o: Dictionary in (load(MODULE) as GDScript).call(&"roll_offers", cfg, seed_value):
			assert_str(str(o["codename"])).starts_with("Operation ")
			assert_bool((cfg["types"] as Dictionary).has(o["type"])).is_true()
			assert_str(str(o["type_name"])).is_equal(str(cfg["types"][o["type"]]["name"]))


func test_the_same_seed_rolls_the_same_offers() -> void:
	var cfg: Dictionary = _module.get(&"config")
	var script: GDScript = load(MODULE)
	assert_array(script.call(&"roll_offers", cfg, 5)).is_equal(script.call(&"roll_offers", cfg, 5))


func test_choosing_sets_the_mission_for_everyone() -> void:
	assert_bool(_module.call(&"server_choose", 7, 1)).is_true()
	var current: Dictionary = _module.get(&"current")
	assert_str(str(current["id"])).is_equal(str((_module.get(&"offers") as Array)[1]["id"]))
	assert_bool(_module.call(&"server_choose", 7, 9)).is_false()


func test_riding_out_takes_everyone_at_home_and_nobody_else() -> void:
	var home := _spawn(11, SPAWN + Vector3(1, 0, 3))
	var away := _spawn(12, SPAWN + Vector3(0, 0, -200))
	assert_bool(_module.call(&"server_ride_out")).is_false()
	_module.call(&"server_choose", 11, 0)
	assert_bool(_module.call(&"server_ride_out")).is_true()
	assert_str(str(_module.get(&"state"))).is_equal("in_mission")
	var dropoff: Vector3 = _module.call(&"dropoff_of", _module.get(&"current"))
	assert_float(home.global_position.distance_to(dropoff)).is_less(8.0)
	assert_vector(away.global_position).is_equal(SPAWN + Vector3(0, 0, -200))
	# No second pick while out.
	assert_bool(_module.call(&"server_choose", 11, 1)).is_false()


func test_riding_home_brings_back_those_near_the_car_and_ends_the_run() -> void:
	var first := _spawn(21, SPAWN + Vector3(1, 0, 3))
	var second := _spawn(22, SPAWN + Vector3(-1, 0, 3))
	_module.call(&"server_choose", 21, 0)
	_module.call(&"server_ride_out")
	await get_tree().process_frame
	# The second wanders off; only the first rides home.
	second.global_position += Vector3(60, 0, 0)
	assert_bool(_module.call(&"server_ride_home", first)).is_true()
	assert_float(first.global_position.distance_to(SPAWN)).is_less(5.0)
	assert_str(str(_module.get(&"state"))).is_equal("in_mission")
	second.global_position -= Vector3(60, 0, 0)
	assert_bool(_module.call(&"server_ride_home", second)).is_true()
	assert_str(str(_module.get(&"state"))).is_equal("home")
	assert_dict(_module.get(&"current")).is_empty()


func test_dying_out_there_counts_as_home() -> void:
	var player := _spawn(31, SPAWN + Vector3(1, 0, 3))
	_module.call(&"server_choose", 31, 0)
	_module.call(&"server_ride_out")
	EventBus.publish(&"player.respawned", {"player": player})
	assert_str(str(_module.get(&"state"))).is_equal("home")


func test_f_at_the_board_is_claimed() -> void:
	var player := _spawn(41, SPAWN)
	await get_tree().process_frame
	var board := _module.get_node("MissionBoard") as Node3D
	# Stand in front of the board and look at it.
	player.global_position = board.global_position + Vector3(-1.6, 0.0, 0.0)
	player.look_at(board.global_position + Vector3(0, player.global_position.y - board.global_position.y, 0), Vector3.UP)
	var opened := []
	var on_open := func(p: Dictionary) -> void: opened.append(p)
	EventBus.subscribe(&"missions.board_opened", on_open)
	var payload := {"player": player}
	EventBus.publish(&"player.interact", payload)
	EventBus.unsubscribe(&"missions.board_opened", on_open)
	assert_bool(payload.get("handled", false)).is_true()
	assert_str(str(_module.call(&"facing", player))).is_equal("board")

extends GdUnitTestSuite
## Glowsticks on the server (#447): cracking uses one up and lights it, it burns out, stowing
## hides it while it keeps burning, dropping leaves it lit on the ground, and a data share of
## soldiers show one at night on patrol only. Every stick is its carrier's band colour.

const PLAYER := "res://modules/player/scenes/player.tscn"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const MODULE := "res://modules/glowsticks/glowsticks_module.gd"
const DAYTIME := "res://modules/daytime/daytime_module.gd"
## Stands in for the enemies module: a soldier is on patrol while its `patrolling` meta says so.
const ENEMIES := "extends Node\nfunc _ready() -> void:\n\tadd_to_group(&\"enemies_api\")\nfunc is_patrolling(soldier: Node) -> bool:\n\treturn soldier.get_meta(&\"patrolling\", true)\n"

var _inventory: Node
var _module: Node
var _states: Array[Dictionary] = []


func before_test() -> void:
	Armband.use_config(Data.load_json(Armband.CONFIG))
	_inventory = auto_free((load(INVENTORY) as GDScript).new())
	add_child(_inventory)
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)
	var script := GDScript.new()
	script.source_code = ENEMIES
	script.reload()
	var enemies: Node = auto_free(Node.new())
	enemies.set_script(script)
	add_child(enemies)
	_states.clear()
	EventBus.subscribe(&"glowsticks.state", _on_state)


func after_test() -> void:
	EventBus.unsubscribe(&"glowsticks.state", _on_state)


func _on_state(state: Dictionary) -> void:
	_states.append(state)


func _spawn(peer: int) -> PlayerController:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", peer)
	player.add_to_group(&"players")
	add_child(player)
	EventBus.publish(&"player.spawned", {"player": player, "local": false})
	return player


func _soldier(peer: int, faction: String, at: Vector3) -> Node3D:
	var soldier: Node3D = auto_free(Node3D.new())
	soldier.set_meta(&"peer_id", peer)
	soldier.set_meta(&"faction", faction)
	soldier.set_meta(&"team", faction)
	soldier.add_to_group(&"enemies")
	add_child(soldier)
	soldier.global_position = at
	EventBus.publish(&"player.spawned", {"player": soldier, "local": false, "npc": true})
	return soldier


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _band(key: String) -> Color:
	var cfg := Armband.config()
	var rgb: Array = cfg[key] if cfg.has(key) else (cfg["factions"] as Dictionary)[key]
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))


func _carriers() -> Dictionary:
	return _module.call(&"server_state")["carriers"]


func test_cracking_uses_one_up_and_lights_it_on_the_chest() -> void:
	_spawn(61)
	assert_str(_module.call(&"server_crack", 61)).is_equal("no glowstick")
	assert_bool(_inventory.call(&"server_give", 61, "glowstick")).is_true()
	assert_str(_module.call(&"server_crack", 61)).is_equal("")
	assert_int(_inventory.call(&"count", 61, "glowstick")).is_equal(0)
	var lit: Dictionary = _module.call(&"lit_of", 61)
	assert_bool(lit["shown"]).is_true()
	assert_float(lit["left"]).is_equal(float(_module.get(&"config")["burn_seconds"]))
	# One at a time.
	_inventory.call(&"server_give", 61, "glowstick")
	assert_str(_module.call(&"server_crack", 61)).is_equal("one is already lit")
	assert_int(_inventory.call(&"count", 61, "glowstick")).is_equal(1)
	await _frames(3)
	assert_bool(_states.is_empty()).override_failure_message("clients were never told").is_false()
	var told: Array = (_states.back()["carriers"] as Dictionary)[61]
	assert_bool(told[0]).is_true()


func test_the_crack_key_and_a_right_click_both_crack_one() -> void:
	var player := _spawn(62)
	_inventory.call(&"server_give", 62, "glowstick")
	player.intent().glowstick = true
	await _frames(2)
	assert_bool((_module.call(&"lit_of", 62) as Dictionary).is_empty()).is_false()
	_spawn(63)
	_inventory.call(&"server_give", 63, "glowstick")
	assert_bool(_inventory.call(&"server_use", 63, "glowstick")).is_true()
	assert_bool((_module.call(&"lit_of", 63) as Dictionary).is_empty()).is_false()
	assert_int(_inventory.call(&"count", 63, "glowstick")).is_equal(0)


func test_it_burns_out_and_is_gone() -> void:
	_spawn(64)
	(_module.get(&"config") as Dictionary)["burn_seconds"] = 0.3
	_inventory.call(&"server_give", 64, "glowstick")
	_module.call(&"server_crack", 64)
	await _frames(10)
	assert_bool((_module.call(&"lit_of", 64) as Dictionary).is_empty()).is_false()
	await _frames(20)
	assert_bool((_module.call(&"lit_of", 64) as Dictionary).is_empty()).is_true()
	assert_bool(_carriers().has(64)).is_false()
	# Spent: nothing comes back to the backpack.
	assert_int(_inventory.call(&"count", 64, "glowstick")).is_equal(0)
	await _frames(20)
	assert_bool((_states.back()["carriers"] as Dictionary).has(64)).override_failure_message("clients still see it").is_false()


func test_stowing_hides_it_and_it_keeps_burning() -> void:
	var player := _spawn(65)
	_inventory.call(&"server_give", 65, "glowstick")
	_module.call(&"server_crack", 65)
	player.intent().glowstick = true
	await _frames(2)
	var lit: Dictionary = _module.call(&"lit_of", 65)
	assert_bool(lit["shown"]).is_false()
	var left := float(lit["left"])
	await _frames(30)
	assert_float(float((_module.call(&"lit_of", 65) as Dictionary)["left"])).is_less(left - 0.4)
	assert_bool(_carriers()[65][0]).is_false()
	assert_str(_module.call(&"server_toggle", 65)).is_equal("")
	assert_bool((_module.call(&"lit_of", 65) as Dictionary)["shown"]).is_true()
	assert_str(_module.call(&"server_stow", 66, true)).is_equal("nothing lit")


func test_dropping_leaves_it_lit_on_the_ground_in_the_band_colour() -> void:
	var player := _spawn(67)
	player.global_position = Vector3(5, 0, 5)
	assert_str(_module.call(&"server_drop", 67)).is_equal("nothing lit")
	_inventory.call(&"server_give", 67, "glowstick")
	_module.call(&"server_crack", 67)
	player.intent().glowstick_drop = true
	await _frames(2)
	assert_bool((_module.call(&"lit_of", 67) as Dictionary).is_empty()).is_true()
	var ground: Array = _module.call(&"server_state")["ground"]
	assert_int(ground.size()).is_equal(1)
	assert_float((ground[0][1] as Vector3).distance_to(player.global_position)).is_less(1.0)
	assert_that(ground[0][2]).is_equal(_band("players"))


func test_a_player_who_dies_drops_theirs() -> void:
	var player := _spawn(68)
	_inventory.call(&"server_give", 68, "glowstick")
	_module.call(&"server_crack", 68)
	EventBus.publish(&"player.died", {"player": player, "source": null, "position": player.global_position})
	assert_bool((_module.call(&"lit_of", 68) as Dictionary).is_empty()).is_true()
	assert_int((_module.call(&"server_state")["ground"] as Array).size()).is_equal(1)


func test_soldiers_from_the_share_show_one_at_night_on_patrol_only() -> void:
	var daytime: Node = auto_free((load(DAYTIME) as GDScript).new())
	add_child(daytime)
	daytime.call(&"server_set_hour", 13.0)
	var cfg: Dictionary = _module.get(&"config")
	cfg["enemy_night_share"] = 1.0
	var carrier := _soldier(-10, "militia", Vector3(3, 0, 0))
	cfg["enemy_night_share"] = 0.0
	var without := _soldier(-11, "militia", Vector3(6, 0, 0))
	assert_bool(_module.call(&"soldier_carries", carrier)).is_true()
	assert_bool(_module.call(&"soldier_carries", without)).is_false()
	await _frames(40)
	assert_bool(_carriers().has(-10)).override_failure_message("shown by day").is_false()
	daytime.call(&"server_set_hour", 23.0)
	await _frames(40)
	assert_bool(_carriers().has(-10)).override_failure_message("not shown at night").is_true()
	assert_bool(_carriers().has(-11)).is_false()
	# Fighting or stalking someone, it keeps quiet.
	carrier.set_meta(&"patrolling", false)
	await _frames(40)
	assert_bool(_carriers().has(-10)).override_failure_message("shown while not on patrol").is_false()
	carrier.set_meta(&"patrolling", true)
	await _frames(40)
	assert_bool(_carriers().has(-10)).is_true()
	EventBus.publish(&"enemy.died", {"enemy": carrier, "source": null, "position": carrier.global_position})
	assert_bool(_carriers().has(-10)).is_false()
	var ground: Array = _module.call(&"server_state")["ground"]
	assert_int(ground.size()).is_equal(1)
	assert_that(ground[0][2]).is_equal(_band("militia"))


func test_a_carrier_freed_without_dying_leaves_the_others_lit() -> void:
	var daytime: Node = auto_free((load(DAYTIME) as GDScript).new())
	add_child(daytime)
	daytime.call(&"server_set_hour", 23.0)
	(_module.get(&"config") as Dictionary)["enemy_night_share"] = 1.0
	var gone := _soldier(-20, "militia", Vector3(3, 0, 0))
	_soldier(-21, "militia", Vector3(6, 0, 0))
	await _frames(40)
	assert_bool(_carriers().has(-20)).is_true()
	# A mission closing frees its guards without a death.
	gone.free()
	await _frames(40)
	assert_bool(_carriers().has(-20)).is_false()
	assert_bool(_carriers().has(-21)).override_failure_message("a freed carrier put out the others").is_true()


func test_the_oldest_stick_on_the_ground_goes_out_past_the_cap() -> void:
	(_module.get(&"config") as Dictionary)["ground_max"] = 2.0
	for peer in [71, 72, 73]:
		_spawn(peer)
		_inventory.call(&"server_give", peer, "glowstick")
		_module.call(&"server_crack", peer)
		_module.call(&"server_drop", peer)
	var ground: Array = _module.call(&"server_state")["ground"]
	assert_int(ground.size()).is_equal(2)
	assert_int(int(ground[0][0])).is_greater(1)


func test_a_player_who_leaves_takes_theirs_out_of_the_world() -> void:
	_spawn(74)
	_inventory.call(&"server_give", 74, "glowstick")
	_module.call(&"server_crack", 74)
	Net.peer_left.emit(74)
	assert_bool(_carriers().has(74)).is_false()


func test_without_the_module_a_glowstick_is_not_used_up() -> void:
	remove_child(_module)
	_spawn(75)
	_inventory.call(&"server_give", 75, "glowstick")
	assert_bool(_inventory.call(&"server_use", 75, "glowstick")).is_false()
	assert_int(_inventory.call(&"count", 75, "glowstick")).is_equal(1)
	add_child(_module)

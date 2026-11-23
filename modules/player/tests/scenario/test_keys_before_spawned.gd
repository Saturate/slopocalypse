extends GdUnitTestSuite
## HUD rows built when `player.spawned` fires for the local player (the glowstick row, the
## charge and set-off hints) read their key caps from the InputMap right then. The player's
## own keys must already be registered, or the caps show "?" for the whole session
## (playtest of #447).

const MODULE := "res://modules/player/player_module.gd"
const PLAYER := "res://modules/player/scenes/player.tscn"
const ACTIONS: Array[StringName] = [&"glowstick", &"glowstick_drop", &"charge", &"detonate"]

var _module: Node
var _seen: Dictionary = {}


func before_test() -> void:
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)
	for action in ACTIONS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	_seen.clear()
	EventBus.subscribe(&"player.spawned", _on_spawned)


func after_test() -> void:
	EventBus.unsubscribe(&"player.spawned", _on_spawned)


func _on_spawned(p: Dictionary) -> void:
	if bool(p.get("local", false)):
		for action in ACTIONS:
			_seen[action] = KeyHint.key_for(action)


func test_the_local_players_keys_are_bound_before_others_hear_of_the_spawn() -> void:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	add_child(player)
	_module.call(&"_on_player_ready", player, true)
	assert_dict(_seen).is_equal({&"glowstick": "L", &"glowstick_drop": "K", &"charge": "G", &"detonate": "T"})

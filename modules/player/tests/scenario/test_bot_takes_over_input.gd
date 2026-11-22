extends GdUnitTestSuite
## A session a bot drives (the menu's Benchmark runs `--bot=city`) takes no keyboard or mouse
## for the local player, so every run is the same whoever sits at the machine (#377, playtest
## #401). The menu adds the bot to the session's arguments, not the command line.

const MODULE := "res://modules/player/player_module.gd"
const PLAYER := "res://modules/player/scenes/player.tscn"

var _module: Node


func before_test() -> void:
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)


func after_test() -> void:
	Net.extra_args = PackedStringArray()


func _player() -> PlayerController:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	add_child(player)
	return player


func test_a_bot_from_the_menu_is_seen() -> void:
	assert_str(str(_module.call(&"_bot_behaviour"))).is_empty()
	Net.extra_args = PackedStringArray(["--benchmark", "--bot=city"])
	assert_str(str(_module.call(&"_bot_behaviour"))).is_equal("city")


func test_a_player_a_bot_drives_gets_no_keyboard_and_mouse() -> void:
	Net.extra_args = PackedStringArray(["--bot=city"])
	var player := _player()
	_module.call(&"_setup_local", player)
	assert_object(player.get_node_or_null("Input")).is_null()
	# Everything else a local player has stays: the HUD and the camera feel.
	assert_object(player.get_node_or_null("Hud")).is_not_null()
	assert_object(player.get_node_or_null("CameraFeel")).is_not_null()


func test_without_a_bot_the_player_reads_keyboard_and_mouse() -> void:
	var player := _player()
	_module.call(&"_setup_local", player)
	assert_object(player.get_node_or_null("Input")).is_not_null()

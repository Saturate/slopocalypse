extends GdUnitTestSuite
## The modding screen edits a draft, shows how its stats compare, and only Apply sends it.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"

var _module: Node
var _player: PlayerController
var _screen: ModdingScreen


func before_test() -> void:
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)
	_player = auto_free((load(PLAYER) as PackedScene).instantiate())
	_player.set_meta(&"peer_id", 1)
	_player.add_to_group(&"players")
	add_child(_player)
	EventBus.publish(&"player.spawned", {"player": _player, "local": false})
	_screen = auto_free(ModdingScreen.new())
	_screen.weapons = _module
	_screen.player = _player
	add_child(_screen)
	_screen.open()


func after_test() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_picking_a_scope_shows_it_magnifies_and_aims_slower() -> void:
	_screen.select("optic", "opt_scope_4x")
	var rows := {}
	for row in _screen.shown_stats():
		rows[row["key"]] = row
	assert_int(rows["magnification"]["verdict"]).is_equal(1)
	assert_int(rows["ads_seconds"]["verdict"]).is_equal(-1)


func test_nothing_changes_until_apply() -> void:
	_screen.select("magazine", "mag_ar_45")
	assert_str(_module.call(&"build_of", 1)["magazine"]).is_equal("mag_ar_30")
	_screen.apply()
	await get_tree().process_frame
	assert_str(_module.call(&"build_of", 1)["magazine"]).is_equal("mag_ar_45")
	assert_bool(_screen.is_open()).is_false()


func test_a_preset_loads_into_the_draft() -> void:
	_screen.load_preset("ar_dmr")
	assert_str(_screen.draft()["optic"]).is_equal("opt_scope_4x")

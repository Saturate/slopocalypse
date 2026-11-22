extends GdUnitTestSuite
## The colour-blind setting (#447): turning it on in Settings repaints the bands of everyone
## already in the world at once, through the player module.

const MODULE := "res://modules/player/player_module.gd"
const PLAYER := "res://modules/player/scenes/player.tscn"


func before() -> void:
	Armband.enabled = true


func after() -> void:
	Armband.enabled = DisplayServer.get_name() != "headless"


func after_test() -> void:
	Settings.set_value(Armband.SETTING, false)


func test_the_setting_repaints_bands_already_worn() -> void:
	Settings.set_value(Armband.SETTING, false)
	Armband.use_config(Data.load_json(Armband.CONFIG))
	add_child(auto_free((load(MODULE) as GDScript).new()))
	var civilian: Node3D = auto_free((load(PLAYER) as PackedScene).instantiate())
	civilian.set_meta(&"team", "civilians")
	civilian.set_meta(&"civilian", true)
	add_child(civilian)
	var band := civilian.get_node(Armband.BAND) as GeometryInstance3D
	var before := (band.material_override as StandardMaterial3D).albedo_color
	Settings.set_value(Armband.SETTING, true)
	var after := (band.material_override as StandardMaterial3D).albedo_color
	assert_that(after).is_not_equal(before)
	assert_that(after).is_equal(Armband.colour_of("civilians"))

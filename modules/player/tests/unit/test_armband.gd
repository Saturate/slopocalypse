extends GdUnitTestSuite
## Armbands (#447): each kind of person wears the band colour armbands.json gives their side,
## read from the metas the server sets as it spawns them. The colour-blind setting swaps in
## the file's second table, live, and that table stays told apart without red-green vision.

const PLAYER := "res://modules/player/scenes/player.tscn"
const FACTIONS := "res://modules/factions/data/factions.json"
## OKLab distance (ColourVision) every two bands of the colour-blind set keep in daylight, as
## seen with each kind of colour blindness. 0.1 is plainly different side by side; bands are
## only a few pixels at fighting range, so they keep more.
const APART := {&"normal": 0.15, &"protan": 0.15, &"deutan": 0.15, &"tritan": 0.15}
## A sunlit band in a noon capture comes out about FLOOR + SCALE x its colour, per channel:
## sun and glow lift every band towards white, which squeezes light colours together.
const DAYLIGHT_FLOOR := 0.3
const DAYLIGHT_SCALE := 0.72
## What the pairs that matter most keep (friend against soldier, regulars against militia,
## who fight each other) for normal and red-green colour-blind eyes.
const RIVALS_APART := 0.18

var _cfg: Dictionary


func after() -> void:
	Armband.enabled = DisplayServer.get_name() != "headless"


func before() -> void:
	Armband.enabled = true


func before_test() -> void:
	Settings.set_value(Armband.SETTING, false)
	Armband.use_config(Data.load_json(Armband.CONFIG))
	_cfg = Armband.config()


func after_test() -> void:
	Settings.set_value(Armband.SETTING, false)


func _person(metas: Dictionary) -> Node3D:
	var person: Node3D = auto_free((load(PLAYER) as PackedScene).instantiate())
	for key: String in metas:
		person.set_meta(StringName(key), metas[key])
	return person


func _expected(c: Array) -> Color:
	return Color(float(c[0]), float(c[1]), float(c[2]))


func _band_colour(person: Node3D) -> Color:
	Armband.apply(person)
	var band := person.get_node(Armband.BAND) as GeometryInstance3D
	return (band.material_override as StandardMaterial3D).albedo_color


func test_config_loads() -> void:
	assert_bool(_cfg.is_empty()).is_false()


func test_a_player_wears_the_players_colour() -> void:
	assert_that(_band_colour(_person({}))).is_equal(_expected(_cfg["players"]))


func test_a_civilian_wears_the_civilians_colour() -> void:
	var civilian := _person({"team": "civilians", "faction": "", "civilian": true})
	assert_that(_band_colour(civilian)).is_equal(_expected(_cfg["civilians"]))


func test_a_soldier_without_a_faction_wears_the_enemies_colour() -> void:
	var soldier := _person({"team": "enemies", "faction": "", "civilian": false})
	assert_that(_band_colour(soldier)).is_equal(_expected(_cfg["enemies"]))


func test_a_faction_soldier_wears_their_factions_colour() -> void:
	var factions: Dictionary = _cfg["factions"]
	for faction: String in factions:
		var soldier := _person({"team": faction, "faction": faction, "civilian": false})
		assert_that(_band_colour(soldier)).override_failure_message(faction).is_equal(_expected(factions[faction]))


func test_a_faction_without_a_colour_wears_the_enemies_colour() -> void:
	var soldier := _person({"team": "newcomers", "faction": "newcomers", "civilian": false})
	assert_that(_band_colour(soldier)).is_equal(_expected(_cfg["enemies"]))


func test_sides_are_told_apart() -> void:
	var colours := [_expected(_cfg["players"]), _expected(_cfg["civilians"]), _expected(_cfg["enemies"])]
	for i in colours.size():
		for j in range(i + 1, colours.size()):
			assert_that(colours[i]).is_not_equal(colours[j])


func test_a_spawned_copy_wears_its_band_from_the_metas_it_arrived_with() -> void:
	# As the spawner hands it over: metas first, then into the tree.
	var civilian := _person({"team": "civilians", "faction": "", "civilian": true})
	add_child(civilian)
	var band := civilian.get_node(Armband.BAND) as GeometryInstance3D
	assert_that((band.material_override as StandardMaterial3D).albedo_color).is_equal(_expected(_cfg["civilians"]))


func test_no_faction_looks_like_a_partner_or_a_civilian() -> void:
	var factions: Dictionary = _cfg["factions"]
	for faction: String in factions:
		var c := _expected(factions[faction])
		assert_that(c).override_failure_message(faction).is_not_equal(_expected(_cfg["players"]))
		assert_that(c).override_failure_message(faction).is_not_equal(_expected(_cfg["civilians"]))


func test_a_uniform_tint_leaves_the_band_alone() -> void:
	var soldier := _person({"team": "enemies", "faction": "", "civilian": false})
	var colour := _band_colour(soldier)
	var uniform := StandardMaterial3D.new()
	uniform.albedo_color = Color(0.1, 0.9, 0.1)
	for path in ["Body/Skeleton/Mesh", "Body/Skeleton/Arms"]:
		(soldier.get_node(path) as GeometryInstance3D).material_override = uniform
	var band := soldier.get_node(Armband.BAND) as GeometryInstance3D
	assert_that((band.material_override as StandardMaterial3D).albedo_color).is_equal(colour)


func test_every_faction_has_its_own_colour() -> void:
	if not FileAccess.file_exists(FACTIONS):
		return
	var factions: Dictionary = (Data.load_json(FACTIONS) as Dictionary)["factions"]
	var colours: Dictionary = _cfg["factions"]
	for faction: String in factions:
		assert_bool(colours.has(faction)).override_failure_message("no armband for " + faction).is_true()


func test_the_band_is_on_both_upper_arms() -> void:
	var person := _person({})
	var band := person.get_node(Armband.BAND) as MeshInstance3D
	var skeleton := band.get_node(band.skeleton) as Skeleton3D
	var arrays := (band.mesh as ArrayMesh).surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var used := {}
	for i in bones.size():
		if weights[i] > 0.0:
			used[skeleton.get_bone_name(bones[i])] = true
	assert_array(used.keys()).contains_exactly_in_any_order(["UpperArm_L", "UpperArm_R"])


func _daylit(c: Color) -> Color:
	return Color(DAYLIGHT_FLOOR + DAYLIGHT_SCALE * c.r, DAYLIGHT_FLOOR + DAYLIGHT_SCALE * c.g, DAYLIGHT_FLOOR + DAYLIGHT_SCALE * c.b)


func _kinds(table: Dictionary) -> Dictionary:
	var out := {"players": _expected(table["players"]), "civilians": _expected(table["civilians"]), "enemies": _expected(table["enemies"])}
	var factions: Dictionary = table["factions"]
	for faction: String in factions:
		out["factions/" + faction] = _expected(factions[faction])
	return out


func test_the_setting_picks_the_colour_blind_table() -> void:
	var blind: Dictionary = _cfg["colour_blind"]
	Settings.set_value(Armband.SETTING, true)
	var civilian := _person({"team": "civilians", "faction": "", "civilian": true})
	assert_that(_band_colour(civilian)).is_equal(_expected(blind["civilians"]))
	var militia := _person({"team": "militia", "faction": "militia", "civilian": false})
	assert_that(_band_colour(militia)).is_equal(_expected((blind["factions"] as Dictionary)["militia"]))


func _worn(person: Node3D) -> Color:
	return ((person.get_node(Armband.BAND) as GeometryInstance3D).material_override as StandardMaterial3D).albedo_color


func test_switching_repaints_bands_already_worn() -> void:
	var blind: Dictionary = _cfg["colour_blind"]
	var civilian := _person({"team": "civilians", "faction": "", "civilian": true})
	var soldier := _person({"team": "regulars", "faction": "regulars", "civilian": false})
	_band_colour(civilian)
	_band_colour(soldier)
	Settings.set_value(Armband.SETTING, true)
	Armband.repaint()
	assert_that(_worn(civilian)).is_equal(_expected(blind["civilians"]))
	assert_that(_worn(soldier)).is_equal(_expected((blind["factions"] as Dictionary)["regulars"]))
	Settings.set_value(Armband.SETTING, false)
	Armband.repaint()
	assert_that(_worn(civilian)).is_equal(_expected(_cfg["civilians"]))


func test_a_switch_made_with_nobody_listening_shows_on_the_next_band() -> void:
	# On the title screen no player module is there to repaint.
	var blind: Dictionary = _cfg["colour_blind"]
	_band_colour(_person({"team": "civilians", "faction": "", "civilian": true}))
	Settings.set_value(Armband.SETTING, true)
	var next := _person({"team": "civilians", "faction": "", "civilian": true})
	assert_that(_band_colour(next)).is_equal(_expected(blind["civilians"]))


func test_every_faction_has_a_colour_in_both_sets() -> void:
	if not FileAccess.file_exists(FACTIONS):
		return
	var factions: Dictionary = (Data.load_json(FACTIONS) as Dictionary)["factions"]
	for table: Dictionary in [_cfg, _cfg["colour_blind"]]:
		var colours: Dictionary = table["factions"]
		for faction: String in factions:
			assert_bool(colours.has(faction)).override_failure_message("no armband for " + faction).is_true()


func test_the_sets_differ_where_red_green_fails() -> void:
	var normal := _kinds(_cfg)
	var blind := _kinds(_cfg["colour_blind"])
	for kind: String in ["civilians", "enemies", "factions/regulars", "factions/militia", "factions/scavengers"]:
		assert_that(blind[kind]).override_failure_message(kind).is_not_equal(normal[kind])


func test_friends_and_soldiers_keep_furthest_apart() -> void:
	# Partners and civilians are the one pair allowed to sit close (both are not to be shot);
	# every soldier keeps well clear of both.
	var blind := _kinds(_cfg["colour_blind"])
	for vision: StringName in [ColourVision.NORMAL, ColourVision.PROTAN, ColourVision.DEUTAN]:
		for friend: String in ["players", "civilians"]:
			for soldier: String in ["enemies", "factions/regulars", "factions/militia", "factions/scavengers"]:
				var apart := ColourVision.difference(_daylit(blind[friend]), _daylit(blind[soldier]), vision)
				assert_float(apart).override_failure_message("%s: %s vs %s %.3f" % [vision, friend, soldier, apart]).is_greater_equal(RIVALS_APART)


func test_the_colour_blind_set_is_told_apart_in_daylight_with_every_kind_of_colour_blindness() -> void:
	var blind := _kinds(_cfg["colour_blind"])
	# Factions sharing the enemies' colour on purpose are one band.
	var seen := {}
	for kind: String in blind:
		seen[blind[kind].to_html(false)] = kind
	var names: Array = seen.keys()
	for vision: StringName in APART:
		for i in names.size():
			for j in range(i + 1, names.size()):
				var a := _daylit(Color.html(names[i]))
				var b := _daylit(Color.html(names[j]))
				var apart := ColourVision.difference(a, b, vision)
				assert_float(apart).override_failure_message("%s: %s vs %s %.3f" % [vision, seen[names[i]], seen[names[j]], apart]).is_greater_equal(float(APART[vision]))


func test_regulars_and_militia_stay_well_apart() -> void:
	var blind := _kinds(_cfg["colour_blind"])
	for vision: StringName in [ColourVision.NORMAL, ColourVision.PROTAN, ColourVision.DEUTAN]:
		var apart := ColourVision.difference(_daylit(blind["factions/regulars"]), _daylit(blind["factions/militia"]), vision)
		assert_float(apart).override_failure_message("%s %.3f" % [vision, apart]).is_greater_equal(RIVALS_APART)


func test_a_file_without_the_colour_blind_table_keeps_the_default_colours() -> void:
	var old: Dictionary = (Data.load_json(Armband.CONFIG) as Dictionary).duplicate(true)
	old.erase("colour_blind")
	Armband.use_config(old)
	Settings.set_value(Armband.SETTING, true)
	var civilian := _person({"team": "civilians", "faction": "", "civilian": true})
	assert_that(_band_colour(civilian)).is_equal(_expected(old["civilians"]))

extends GdUnitTestSuite
## Armbands (#447): each kind of person wears the band colour armbands.json gives their side,
## read from the metas the server sets as it spawns them.

const PLAYER := "res://modules/player/scenes/player.tscn"
const FACTIONS := "res://modules/factions/data/factions.json"

var _cfg: Dictionary


func after() -> void:
	Armband.enabled = DisplayServer.get_name() != "headless"


func before() -> void:
	Armband.enabled = true
	Armband.use_config(Data.load_json(Armband.CONFIG))
	_cfg = Armband.config()


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

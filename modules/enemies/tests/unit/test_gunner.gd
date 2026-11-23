extends GdUnitTestSuite
## Some squads bring a gunner: one soldier wearing the faction's gunner gear (the machine
## gun) instead of its usual gun, as often as the faction's data says, and known as the
## gunner by that gear.

const MODULE := "res://modules/enemies/enemies_module.gd"
const FACTIONS := "res://modules/factions/data/factions.json"

var _faction := {
	"gear": {"primary": "gun_rifle", "rig": "rig_heavy"},
	"marksman": {"squad_chance": 0.25, "gear": {"primary": "gun_bolt"}},
	"gunner": {"squad_chance": 0.3, "gear": {"primary": "gun_mg"}},
}


func _module() -> GDScript:
	return load(MODULE) as GDScript


func _gear(faction: Dictionary, roll: float) -> Dictionary:
	return _module().call(&"role_gear", faction, "gunner", roll)


func _is_gunner(faction: Dictionary, gear: Variant) -> bool:
	return bool(_module().call(&"is_gunner", faction, gear))


func test_a_squad_under_the_chance_brings_a_gunner_with_the_machine_gun() -> void:
	var gear := _gear(_faction, 0.2)
	assert_str(str(gear.get("primary", ""))).is_equal("gun_mg")
	assert_str(str(gear.get("rig", ""))).is_equal("rig_heavy")


func test_a_squad_over_the_chance_has_none() -> void:
	assert_dict(_gear(_faction, 0.3)).is_empty()


func test_the_gunner_is_known_by_its_gear_and_nobody_else_is() -> void:
	assert_bool(_is_gunner(_faction, _gear(_faction, 0.0))).is_true()
	assert_bool(_is_gunner(_faction, _module().call(&"role_gear", _faction, "marksman", 0.0))).is_false()
	assert_bool(_is_gunner(_faction, _faction["gear"])).is_false()
	assert_bool(_is_gunner(_faction, null)).is_false()
	# A faction without gunners has none, whatever they wear.
	assert_bool(_is_gunner({"gear": {"primary": "gun_mg"}}, {"primary": "gun_mg"})).is_false()


func test_the_factions_gunners_carry_the_machine_gun() -> void:
	var data: Dictionary = Data.load_json(FACTIONS)
	var with_gunners := 0
	for id: String in data["factions"]:
		var faction: Dictionary = data["factions"][id]
		if faction.has("gunner"):
			with_gunners += 1
			assert_str(str(_gear(faction, 0.0).get("primary", ""))).is_equal("gun_mg")
			# Some squads, not every one.
			assert_float(float(faction["gunner"]["squad_chance"])).is_between(0.05, 0.5)
	assert_int(with_gunners).is_greater(0)

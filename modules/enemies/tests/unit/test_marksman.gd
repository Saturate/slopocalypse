extends GdUnitTestSuite
## Some squads bring a marksman: one soldier wearing the faction's marksman gear (a
## bolt-action rifle) instead of its usual gun, as often as the faction's data says.

const MODULE := "res://modules/enemies/enemies_module.gd"
const FACTIONS := "res://modules/factions/data/factions.json"

var _faction := {
	"gear": {"primary": "gun_rifle", "rig": "rig_light"},
	"marksman": {"squad_chance": 0.25, "gear": {"primary": "gun_bolt"}},
}


func _gear(faction: Dictionary, roll: float) -> Dictionary:
	return (load(MODULE) as GDScript).call(&"role_gear", faction, "marksman", roll)


func test_a_squad_under_the_chance_brings_a_marksman_in_the_factions_other_gear() -> void:
	var gear := _gear(_faction, 0.1)
	assert_str(str(gear.get("primary", ""))).is_equal("gun_bolt")
	# Everything else as the rest of the faction wears it.
	assert_str(str(gear.get("rig", ""))).is_equal("rig_light")


func test_a_squad_over_the_chance_has_none() -> void:
	assert_dict(_gear(_faction, 0.3)).is_empty()


func test_a_faction_without_marksmen_never_has_one() -> void:
	assert_dict(_gear({"gear": {"primary": "gun_rifle"}}, 0.0)).is_empty()


func test_the_factions_marksmen_carry_the_bolt_action() -> void:
	var data: Dictionary = Data.load_json(FACTIONS)
	var with_marksmen := 0
	for id: String in data["factions"]:
		var faction: Dictionary = data["factions"][id]
		if faction.has("marksman"):
			with_marksmen += 1
			assert_str(str(_gear(faction, 0.0).get("primary", ""))).is_equal("gun_bolt")
			# A few squads, not every one.
			assert_float(float(faction["marksman"]["squad_chance"])).is_between(0.05, 0.5)
	assert_int(with_marksmen).is_greater(0)

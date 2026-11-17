extends Node
## Soldier factions (#343): their looks, gear and leanings, and who is hostile to whom
## (FactionRules). Other modules ask through the `factions_api` group and work without it
## (one side, "enemies", hostile to players only).

const CONFIG := "res://modules/factions/data/factions.json"
const REQUIRED := {"factions": TYPE_DICTIONARY, "relations": TYPE_ARRAY, "default_relation": TYPE_FLOAT, "hostile_below": TYPE_FLOAT, "guard_faction": TYPE_STRING}

var rules: FactionRules


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not (data is Dictionary and Data.require(CONFIG, data, REQUIRED)):
		return
	rules = FactionRules.new(data)
	add_to_group(&"factions_api")


func hostile(a: String, b: String) -> bool:
	return rules.hostile(a, b)


func pick(rng: RandomNumberGenerator) -> String:
	return rules.pick(rng)


func info(id: String) -> Dictionary:
	return rules.info(id)


func guard_faction() -> String:
	return str(rules.data["guard_faction"])

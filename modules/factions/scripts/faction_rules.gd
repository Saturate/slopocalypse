class_name FactionRules
extends RefCounted
## Who is hostile to whom (#343): relations between factions from -100 to 100, hostile below
## a line; players are hostile to every faction for now (standing per player comes next).
## Pure, so the server and tests ask it the same way. Moves to Rust once standing and the
## off-screen fights settle (AGENTS.md rule 9).

const PLAYERS := "players"

## `data`: factions.json.
var data: Dictionary = {}
var _relations: Dictionary = {}


func _init(config: Dictionary) -> void:
	data = config
	for r: Array in config.get("relations", []):
		_relations[_key(str(r[0]), str(r[1]))] = float(r[2])


static func _key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


func ids() -> Array:
	return (data.get("factions", {}) as Dictionary).keys()


func has(id: String) -> bool:
	return (data.get("factions", {}) as Dictionary).has(id)


func info(id: String) -> Dictionary:
	return (data.get("factions", {}) as Dictionary).get(id, {})


## Between two factions; the same faction is fully friendly.
func relation(a: String, b: String) -> float:
	if a == b:
		return 100.0
	return float(_relations.get(_key(a, b), data.get("default_relation", 0.0)))


## Whether sides `a` and `b` (faction ids, or "players") fight on sight.
func hostile(a: String, b: String) -> bool:
	if a.is_empty() or b.is_empty() or a == b:
		return false
	if a == PLAYERS or b == PLAYERS:
		return true
	return relation(a, b) < float(data.get("hostile_below", -30.0))


## A faction for a new squad, by weight.
func pick(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for id: String in ids():
		total += float(info(id).get("weight", 1.0))
	var roll := rng.randf() * total
	for id: String in ids():
		roll -= float(info(id).get("weight", 1.0))
		if roll <= 0.0:
			return id
	return ids()[0] if not ids().is_empty() else ""

class_name FactionRules
extends RefCounted
## Who is hostile to whom (#343): relations between factions, and each player's standing with
## each faction, both from -100 to 100 in the same bands (hostile, neutral, friendly,
## allied). Killing a faction's soldier lowers your standing with it and raises it with every
## faction hostile to it. Pure, so the server and tests ask it the same way. Moves to Rust
## once the off-screen fights settle (AGENTS.md rule 9).

const PLAYERS := "players"

## `data`: factions.json.
var data: Dictionary = {}
var _relations: Dictionary = {}
## player key (their name) -> {faction: standing}; only what has moved from the start.
var _standing: Dictionary = {}


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


## "hostile", "neutral", "friendly" or "allied" for a relation or standing value.
func band(value: float) -> String:
	if value < float(data.get("hostile_below", -30.0)):
		return "hostile"
	if value > float(data.get("allied_above", 70.0)):
		return "allied"
	if value > float(data.get("friendly_above", 30.0)):
		return "friendly"
	return "neutral"


func _standing_config() -> Dictionary:
	return data.get("standing", {})


func start_standing(faction: String) -> float:
	var cfg := _standing_config()
	return float((cfg.get("start", {}) as Dictionary).get(faction, cfg.get("default_start", -50.0)))


## `player`'s standing with `faction`.
func standing(player: String, faction: String) -> float:
	var mine: Dictionary = _standing.get(player, {})
	return float(mine.get(faction, start_standing(faction)))


## Every faction's standing for `player`, for the faction screen and the save.
func standing_of(player: String) -> Dictionary:
	var out := {}
	for id: String in ids():
		out[id] = standing(player, id)
	return out


## Puts back a saved standing; unknown factions are dropped, values clamped.
func set_standing_of(player: String, values: Dictionary) -> void:
	var mine := {}
	for id: Variant in values:
		if has(str(id)):
			mine[str(id)] = clampf(float(values[id]), -100.0, 100.0)
	_standing[player] = mine


func adjust(player: String, faction: String, delta: float) -> void:
	if not has(faction) or delta == 0.0:
		return
	var mine: Dictionary = _standing.get(player, {})
	mine[faction] = clampf(standing(player, faction) + delta, -100.0, 100.0)
	_standing[player] = mine


## Whether `faction`'s soldiers shoot `player` on sight.
func hostile_to_player(faction: String, player: String) -> bool:
	if faction.is_empty() or not has(faction):
		return true
	return band(standing(player, faction)) == "hostile"


## `player` killed a soldier of `victim`: worse with them, better with their enemies.
func record_kill(player: String, victim: String) -> void:
	if not has(victim):
		return
	var cfg := _standing_config()
	adjust(player, victim, float(cfg.get("kill_member", -25.0)))
	for other: String in ids():
		if other != victim and hostile(other, victim):
			adjust(player, other, float(cfg.get("kill_rival", 6.0)))


## `player` hurt (but didn't kill) a soldier of `victim`.
func record_hurt(player: String, victim: String) -> void:
	adjust(player, victim, float(_standing_config().get("hurt_member", -3.0)))

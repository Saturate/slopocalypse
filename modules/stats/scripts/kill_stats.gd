class_name KillStats
extends RefCounted
## Counters per player, by name: kills by kind (and soldiers by faction), deaths by what
## killed you, headshots and the longest kill. Pure, so the server and tests use it the same
## way; the stats module feeds it from death events and persistence saves it.
##
## Keys: kills.soldier, kills.soldier.<faction>, kills.player, kills.drone, deaths,
## deaths.<soldier|player|drone|self|other>, headshots, longest_kill (metres).

const LONGEST := "longest_kill"

## name -> {key: value}
var _by_player: Dictionary = {}


func of(player: String) -> Dictionary:
	return (_by_player.get(player, {}) as Dictionary).duplicate()


func value(player: String, key: String) -> float:
	return float((_by_player.get(player, {}) as Dictionary).get(key, 0.0))


func set_of(player: String, values: Dictionary) -> void:
	var clean := {}
	for key: Variant in values:
		clean[str(key)] = maxf(float(values[key]), 0.0)
	_by_player[player] = clean


func add(player: String, key: String, amount := 1.0) -> void:
	var mine: Dictionary = _by_player.get(player, {})
	mine[key] = float(mine.get(key, 0.0)) + amount
	_by_player[player] = mine


## `player` killed something of `kind` ("soldier", "player", "drone"), `metres` away;
## soldiers also count under their faction.
func record_kill(player: String, kind: String, faction: String, metres: float) -> void:
	add(player, "kills." + kind)
	if kind == "soldier" and not faction.is_empty():
		add(player, "kills.soldier." + faction)
	var mine: Dictionary = _by_player.get(player, {})
	mine[LONGEST] = maxf(float(mine.get(LONGEST, 0.0)), metres)
	_by_player[player] = mine


## `player` died to something of `kind` ("soldier", "player", "drone", "self", "other").
func record_death(player: String, kind: String) -> void:
	add(player, "deaths")
	add(player, "deaths." + kind)


## Every player's counts added up (longest kill: the longest), for the server's status page.
func totals() -> Dictionary:
	var out := {}
	for player: String in _by_player:
		var mine: Dictionary = _by_player[player]
		for key: String in mine:
			if key == LONGEST:
				out[key] = maxf(float(out.get(key, 0.0)), float(mine[key]))
			else:
				out[key] = float(out.get(key, 0.0)) + float(mine[key])
	return out

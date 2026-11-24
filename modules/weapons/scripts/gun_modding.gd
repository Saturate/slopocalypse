class_name GunModding
extends RefCounted
## The rules the modding screen works with, kept out of the UI so they can be tested:
## which parts fit a slot, which slots the current parts make available, swapping a part
## (dropping parts that lose their mount), and comparing two builds' stats. Every part in
## the catalogue is offered until inventory decides what a player owns.

## Mirrors weapons_core::parts::REQUIRED_SLOTS, for receivers that do not name their own.
const REQUIRED: Array[String] = ["receiver", "barrel", "grip", "magazine"]

## Stats the screen compares: key, label, format, whether more is better, and whether to
## leave the row out when both guns have none of it (only bolt-actions have a bolt cycle).
const STAT_ROWS: Array[Dictionary] = [
	{"key": "damage", "label": "Damage", "format": "%.0f", "higher_better": true},
	{"key": "rounds_per_minute", "label": "Fire rate", "format": "%.0f rpm", "higher_better": true},
	{"key": "cycle_seconds", "label": "Bolt cycle", "format": "%.2f s", "higher_better": false, "hide_zero": true},
	{"key": "magazine", "label": "Magazine", "format": "%.0f", "higher_better": true},
	{"key": "range", "label": "Range", "format": "%.0f m", "higher_better": true},
	{"key": "recoil_pitch_degrees", "label": "Recoil", "format": "%.2f", "higher_better": false},
	{"key": "spread_degrees", "label": "Spread", "format": "%.2f", "higher_better": false},
	{"key": "ergonomics", "label": "Ergonomics", "format": "%.0f", "higher_better": true},
	{"key": "ads_seconds", "label": "Aim time", "format": "%.2f s", "higher_better": false},
	{"key": "reload_seconds", "label": "Reload", "format": "%.2f s", "higher_better": false},
	{"key": "magnification", "label": "Magnification", "format": "%.1fx", "higher_better": true},
	{"key": "weight", "label": "Weight", "format": "%.2f kg", "higher_better": false},
]
## A whole gun's numbers for its details on the trade screen: these rows of `STAT_ROWS`.
const GUN_DETAIL_KEYS: Array[String] = ["damage", "rounds_per_minute", "magazine", "range", "reload_seconds"]
## What a single part changes, for its details: key, label and format. Percentages are the
## change to the gun's own value.
const PART_DETAIL_ROWS: Array[Dictionary] = [
	{"key": "magazine", "label": "Magazine", "format": "%.0f rounds"},
	{"key": "range", "label": "Range", "format": "%.0f m"},
	{"key": "magnification", "label": "Magnification", "format": "%.1fx"},
	{"key": "recoil_pct", "label": "Recoil", "format": "%+.0f%%"},
	{"key": "spread_pct", "label": "Spread", "format": "%+.0f%%"},
	{"key": "reload_pct", "label": "Reload time", "format": "%+.0f%%"},
	{"key": "ergonomics", "label": "Ergonomics", "format": "%+.0f"},
	{"key": "weight", "label": "Weight", "format": "%.2f kg"},
]


## Part ids that fit `slot`, by display name.
static func options(slot: String) -> Array[String]:
	var parts := GunAssembly.catalogue()
	var out: Array[String] = []
	for id: String in parts:
		if str((parts[id] as Dictionary).get("slot", "")) == slot:
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool: return display_name(a) < display_name(b))
	return out


static func display_name(part_id: String) -> String:
	return str((GunAssembly.catalogue().get(part_id, {}) as Dictionary).get("name", part_id))


## Every slot a gun on this build's receiver can have, in the order parts provide them:
## the receiver's own slots, then the slots their parts can add (a barrel's muzzle).
static func slots_for(build: Dictionary) -> Array[String]:
	var out: Array[String] = ["receiver"]
	var i := 0
	while i < out.size():
		var slot := out[i]
		var sources: Array[String] = []
		if slot == "receiver":
			sources.append(str(build.get("receiver", "")))
		else:
			sources = options(slot)
		for id in sources:
			for provided: Variant in (GunAssembly.catalogue().get(id, {}) as Dictionary).get("provides", []):
				if not out.has(str(provided)):
					out.append(str(provided))
		i += 1
	return out


## Whether a gun on this build's receiver must have `slot` filled.
static func is_required(slot: String, build: Dictionary = {}) -> bool:
	var named: Array = GunAssembly.receiver_of(build).get("requires", [])
	if named.is_empty():
		return REQUIRED.has(slot)
	return slot == "receiver" or named.has(slot)


## True when a part in `build` provides `slot` (the receiver always is).
static func is_available(slot: String, build: Dictionary) -> bool:
	if slot == "receiver":
		return true
	var parts := GunAssembly.catalogue()
	for fitted: String in build:
		var part: Dictionary = parts.get(str(build[fitted]), {})
		if (part.get("provides", []) as Array).has(slot):
			return true
	return false


## `build` with `slot` set to `part_id` ("" empties it). Parts left without a mount (a
## muzzle device after its barrel goes) come off too.
static func with_part(build: Dictionary, slot: String, part_id: String) -> Dictionary:
	var out := build.duplicate()
	if part_id.is_empty():
		out.erase(slot)
	else:
		out[slot] = part_id
	var changed := true
	while changed:
		changed = false
		for s: String in out.keys():
			if not is_available(s, out):
				out.erase(s)
				changed = true
	return out


## A stat as the screen shows it: the fire rate of a bolt-action is what working the bolt
## allows, not its mechanism's rate.
static func shown_value(stats: Dictionary, key: String) -> float:
	var value := float(stats.get(key, 0.0))
	var cycle := float(stats.get("cycle_seconds", 0.0))
	if key == "rounds_per_minute" and cycle > 0.0 and value > 0.0:
		return 60.0 / maxf(60.0 / value, cycle)
	return value


## A build's stats as the screen compares them: a gun that loads a round at a time shows
## its reload as the time to fill it from empty, not the time for one round.
static func screen_stats(build: Dictionary, stats: Dictionary) -> Dictionary:
	if not GunAssembly.round_by_round_of(build):
		return stats
	var out := stats.duplicate()
	out["reload_seconds"] = float(stats.get("reload_seconds", 0.0)) * float(stats.get("magazine", 0.0))
	return out


## One row per stat: label, both values and the change formatted, and whether the change
## is better (1), worse (-1) or the same (0).
static func compare(before: Dictionary, after: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row in STAT_ROWS:
		var key: String = row["key"]
		var a := shown_value(before, key)
		var b := shown_value(after, key)
		if bool(row.get("hide_zero", false)) and is_zero_approx(a) and is_zero_approx(b):
			continue
		var verdict := 0
		if not is_equal_approx(a, b):
			verdict = 1 if (b > a) == bool(row["higher_better"]) else -1
		var fmt := str(row["format"])
		rows.append({
			"key": key,
			"label": row["label"],
			"before": fmt % a,
			"after": fmt % b,
			# Signed, in the same units: "+15", "-0.03 s".
			"delta": "" if verdict == 0 else fmt.replace("%.", "%+.") % (b - a),
			"verdict": verdict,
		})
	return rows


## `{label, value}` rows for a gun built from `slots`. A launcher's receiver deals no bullet
## damage; its rocket's is what counts.
static func gun_detail_rows(slots: Dictionary) -> Array[Dictionary]:
	var result := WeaponBuild.assemble(GunAssembly.catalogue(), slots)
	var out: Array[Dictionary] = []
	if not result["ok"]:
		return out
	var stats := screen_stats(slots, result["stats"])
	for row in STAT_ROWS:
		var key: String = row["key"]
		if not GUN_DETAIL_KEYS.has(key):
			continue
		var value := shown_value(stats, key)
		if key == "damage" and bool(GunAssembly.receiver_of(slots).get("projectile", false)):
			value = float(RocketLauncher.rocket_config().get("damage", 0.0))
		if is_zero_approx(value):
			continue
		out.append({"label": row["label"], "value": str(row["format"]) % value})
	return out


## `{label, value}` rows for one part's own `stats`.
static func part_detail_rows(stats: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in PART_DETAIL_ROWS:
		var key: String = row["key"]
		if stats.has(key) and not is_zero_approx(float(stats[key])):
			out.append({"label": row["label"], "value": str(row["format"]) % float(stats[key])})
	return out

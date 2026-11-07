class_name GunModding
extends RefCounted
## The rules the modding screen works with, kept out of the UI so they can be tested:
## which parts fit a slot, which slots the current parts make available, swapping a part
## (dropping parts that lose their mount), and comparing two builds' stats. Every part in
## the catalogue is offered until inventory decides what a player owns.

## Mirrors weapons_core::parts::REQUIRED_SLOTS, for receivers that do not name their own.
const REQUIRED: Array[String] = ["receiver", "barrel", "grip", "magazine"]

## Stats the screen compares: key, label, format, and whether more is better.
const STAT_ROWS: Array[Dictionary] = [
	{"key": "damage", "label": "Damage", "format": "%.0f", "higher_better": true},
	{"key": "rounds_per_minute", "label": "Fire rate", "format": "%.0f rpm", "higher_better": true},
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


## One row per stat: label, both values and the change formatted, and whether the change
## is better (1), worse (-1) or the same (0).
static func compare(before: Dictionary, after: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row in STAT_ROWS:
		var key: String = row["key"]
		var a := float(before.get(key, 0.0))
		var b := float(after.get(key, 0.0))
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

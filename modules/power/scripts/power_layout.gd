class_name PowerLayout
extends RefCounted
## Where each piece of the map's power lines stands and which wires hang between them
## (power.json): the substation yard, a terminal gantry in it for each high-voltage line, a
## pylon at every other point of a high-voltage line and a pole at every point of a pole line,
## each turned to bisect the angle its line makes there (MapPower.heading_at), standing on the
## lowest ground under its feet, and every span between neighbours hung from their matching
## attach points. Every high-voltage tower on the map is alike, so the terminals match the
## pylons; a pole line's poles are alike, from a seed made of the line's ends. A pole line
## that taps another starts on one of its poles, which takes a second, lower crossarm turned to
## face the tap (VoxPowerPole `tap`) and the tapped line's parameters. Pure; no autoloads.

const CONFIG := "res://modules/power/data/power.json"
const REQUIRED := {"builds_per_frame": TYPE_FLOAT, "sink": TYPE_FLOAT, "pylon": TYPE_DICTIONARY, "pole": TYPE_DICTIONARY,
	"terminal": TYPE_DICTIONARY, "substation": TYPE_DICTIONARY}
const TOWER := {"generator": TYPE_STRING, "params": TYPE_DICTIONARY, "lods": TYPE_ARRAY, "fade": TYPE_FLOAT}
## The piece spec in power.json for each kind of line's towers.
const SPECS := {"high_voltage": "pylon", "low_voltage": "pole"}
## A tap's arm is turned in steps this many degrees, so taps share a few meshes.
const TAP_STEP := 5.0
## Attach points this close across a span (metres) count as side by side, the higher first.
const SAME_SIDE := 0.01


## What is wrong with power.json past its top-level fields, or empty.
static func check(cfg: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key: String in ["pylon", "pole", "terminal", "substation"]:
		var spec: Dictionary = cfg[key]
		for field: String in TOWER:
			if not spec.has(field) or typeof(spec[field]) != int(TOWER[field]):
				out.append("%s: `%s` should be %s" % [key, field, type_string(int(TOWER[field]))])
		if spec.get("generator") is String:
			var gen := VoxCatalog.by_name(str(spec["generator"]))
			if gen == null or (key != "substation" and not gen.has_method(&"attach_points")):
				out.append("%s: no voxel generator %s%s" % [key, spec["generator"], "" if key == "substation" else " with attach points"])
	return out


## {towers, wires}. `lines` are VoxelWorld.map_power_lines', `station` its
## map_power_substation; `ground(x, z)` the height of the ground. Each tower {kind (a line's
## kind, or "substation"), line (its place in `lines`, -1 for the yard), generator, params,
## lods, fade, transform, attach (world points, in the generator's order), tap (a tap arm's
## world points, or empty)}; each wire set {owner, spans} as the wires module takes them, plus
## `pairs`: [tower, tower, wires hung] per span.
static func plan(lines: Array, station: Dictionary, cfg: Dictionary, ground: Callable) -> Dictionary:
	var towers: Array[Dictionary] = []
	var at: Dictionary[Vector2i, int] = {}
	var line_params: Array[Dictionary] = []
	var wires: Array[Dictionary] = []
	var sink := float(cfg["sink"])
	if not station.is_empty():
		var spec: Dictionary = cfg["substation"]
		var c: Vector3 = station["centre"]
		var base := float(station["base"]) - sink
		var params: Dictionary = (spec["params"] as Dictionary).duplicate()
		params["size"] = float(station["size"])
		params["plinth"] = snappedf(c.y - base, 0.05)
		# The pad's top comes out at the yard's level.
		base = c.y - float(params["plinth"])
		towers.append(_piece("substation", -1, spec, params, Transform3D(Basis.IDENTITY, Vector3(c.x, base, c.z)), [], []))
	# Every high-voltage tower alike, from the substation's place.
	var hv_params := _params(cfg["pylon"], [str(station.get("centre", Vector3.ZERO))])
	for i in lines.size():
		var line: Dictionary = lines[i]
		var kind := str(line["kind"])
		var spec: Dictionary = cfg[SPECS.get(kind, "pole")]
		var points: Array = line["points"]
		var from := str(line["from"])
		var params := hv_params if kind == "high_voltage" else _params(spec, [from, str(line["to"]), str(points[0])])
		var parent := int(from.get_slice(" ", 1)) if from.begins_with("line ") else -1
		if parent >= 0 and parent < line_params.size():
			params = line_params[parent]
		line_params.append(params)
		var gen := VoxCatalog.by_name(str(spec["generator"]))
		var reach := float(gen.with_defaults(params).get("base", 0.0)) / 2.0
		var ids: Array[int] = []
		for k in points.size():
			var key := key_of(points[k])
			if at.has(key):
				ids.append(at[key])
				continue
			var xform := tower_transform(points, k, reach, sink, ground)
			at[key] = towers.size()
			ids.append(towers.size())
			if k == 0 and kind == "high_voltage" and from == "substation":
				# The line's terminal gantry in the yard, on the pad.
				var t_spec: Dictionary = cfg["terminal"]
				var t_params: Dictionary = (t_spec["params"] as Dictionary).duplicate()
				t_params["circuits"] = params.get("circuits", 1)
				t_params["arm"] = gen.with_defaults(params)["arm"]
				var on_pad := Transform3D(xform.basis, points[k])
				towers.append(_piece(kind, i, t_spec, t_params, on_pad, _points_of(t_spec, t_params, on_pad, &"attach_points"), []))
			else:
				towers.append(_piece(kind, i, spec, params, xform, _points_of(spec, params, xform, &"attach_points"), []))
		if parent >= 0 and not ids.is_empty() and points.size() > 1:
			_add_tap(towers[ids[0]], points[1])
		var spans: Array[Dictionary] = []
		var pairs: Array = []
		for k in range(1, ids.size()):
			var a: Dictionary = towers[ids[k - 1]]
			var from_points: Array[Vector3] = a["tap"] if k == 1 and parent >= 0 else a["attach"]
			var hung := pair(a, from_points, towers[ids[k]], towers[ids[k]]["attach"], kind, float(line.get("sag", 0.0)))
			spans.append_array(hung)
			pairs.append([ids[k - 1], ids[k], hung.size()])
		wires.append({"owner": "power/%d" % i, "spans": spans, "pairs": pairs})
	return {"towers": towers, "wires": wires}


static func _piece(kind: String, line: int, spec: Dictionary, params: Dictionary, xform: Transform3D, attach: Array[Vector3], tap: Array[Vector3]) -> Dictionary:
	return {"kind": kind, "line": line, "generator": str(spec["generator"]), "params": params, "lods": spec["lods"], "fade": float(spec["fade"]),
		"transform": xform, "attach": attach, "tap": tap}


static func _points_of(spec: Dictionary, params: Dictionary, xform: Transform3D, method: StringName) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var gen := VoxCatalog.by_name(str(spec["generator"]))
	for p: Vector3 in gen.call(method, params):
		out.append(xform * p)
	return out


## Gives pole `tower` a tap arm facing `toward` (the tap line's next pole): its own copy of
## the parameters with the arm's turn, in TAP_STEP degree steps.
static func _add_tap(tower: Dictionary, toward: Vector3) -> void:
	var xform: Transform3D = tower["transform"]
	var d := Vector2(toward.x - xform.origin.x, toward.z - xform.origin.z)
	var facing := rad_to_deg(atan2(-d.x, -d.y) - xform.basis.get_euler().y)
	var params: Dictionary = (tower["params"] as Dictionary).duplicate()
	params["tap"] = fposmod(snappedf(facing, TAP_STEP), 360.0)
	tower["params"] = params
	var tap: Array[Vector3] = []
	for p: Vector3 in VoxPowerPole.tap_points(params):
		tap.append(xform * p)
	tower["tap"] = tap


## Towers are told apart by where they stand, to the decimetre.
static func key_of(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x * 10.0), roundi(p.z * 10.0))


## A spec's parameters with its `choices` picked from a seed made of `words`. The generator
## seed is the spec's own, so towers alike share their meshes.
static func _params(spec: Dictionary, words: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(words)
	var params: Dictionary = (spec["params"] as Dictionary).duplicate()
	var choices: Dictionary = spec.get("choices", {})
	for key: String in choices:
		var options: Array = choices[key]
		params[key] = options[rng.randi_range(0, options.size() - 1)]
	return params


## Tower `k` of a line through `points`: facing MapPower.heading_at, standing on the lowest
## ground under its middle and its four corner feet (`reach` out along each of its own axes,
## so turned with it), `sink` metres into it.
static func tower_transform(points: Array, k: int, reach: float, sink: float, ground: Callable) -> Transform3D:
	var here: Vector3 = points[k]
	var dir := MapPower.heading_at(points, k)
	var basis := Basis(Vector3.UP, atan2(-dir.x, -dir.y))
	var low: float = ground.call(here.x, here.z)
	if reach > 0.0:
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var foot := here + basis * Vector3(c.x * reach, 0.0, c.y * reach)
			low = minf(low, float(ground.call(foot.x, foot.z)))
	return Transform3D(basis, Vector3(here.x, low - sink, here.z))


## The wires from `from_points` on tower `a` to `to_points` on tower `b`: each set ordered
## across the span, left to right (the higher first where two are side by side), and matched
## in that order, so no two wires cross.
static func pair(a: Dictionary, from_points: Array[Vector3], b: Dictionary, to_points: Array[Vector3], kind: String, sag: float) -> Array[Dictionary]:
	var from: Vector3 = (a["transform"] as Transform3D).origin
	var to: Vector3 = (b["transform"] as Transform3D).origin
	var along := Vector3(to.x - from.x, 0.0, to.z - from.z).normalized()
	var across := Vector3(-along.z, 0.0, along.x)
	var left := _ordered(from_points, from, across)
	var right := _ordered(to_points, to, across)
	var out: Array[Dictionary] = []
	for i in mini(left.size(), right.size()):
		out.append({"from": left[i], "to": right[i], "kind": StringName(kind), "sag": sag})
	return out


static func _ordered(points: Array[Vector3], origin: Vector3, across: Vector3) -> Array[Vector3]:
	var out := points.duplicate()
	out.sort_custom(func(p: Vector3, q: Vector3) -> bool:
		var dp := (p - origin).dot(across)
		var dq := (q - origin).dot(across)
		if absf(dp - dq) > SAME_SIDE:
			return dp < dq
		return p.y > q.y)
	return out

class_name HarbourPlan
extends RefCounted
## What the harbour by the camp is built of (harbour.json) on the map's harbour spot
## (MapShape.harbour): a jetty (VoxJetty) from where the ground meets its deck out over the
## spot's deep water, and the pieces standing about it, each at its anchor (the jetty's shore
## or sea end). Pure; no autoloads.

const CONFIG := "res://modules/harbour/data/harbour.json"
const REQUIRED := {"jetty": TYPE_DICTIONARY, "sink": TYPE_FLOAT, "max_rise": TYPE_FLOAT, "pieces": TYPE_ARRAY}
const JETTY := {"freeboard": TYPE_FLOAT, "step": TYPE_FLOAT, "landing": TYPE_FLOAT, "params": TYPE_DICTIONARY}
const PIECE := {"name": TYPE_STRING, "generator": TYPE_STRING, "anchor": TYPE_STRING, "at": TYPE_ARRAY, "yaw": TYPE_FLOAT, "params": TYPE_DICTIONARY}
const ANCHORS: Array[String] = ["shore", "end"]
## Set by the plan, never by harbour.json's jetty params.
const PLANNED: Array[String] = ["sections", "height", "seed"]
## Metres between the ground samples that look for the jetty's shore end.
const LANDING_STEP := 0.25
## Metres between the ground samples along the jetty for the depth its piles reach down to.
const PILE_STEP := 1.0


## Every piece as {kind ("jetty" or the piece's name), generator, params, transform}; the
## jetty's pieces first, shore end to sea end. `harbour` is MapShape.harbour's (empty: nothing), `ground` answers the
## ground's height at (x, z) as VoxelWorld.ground_height does.
static func plan(harbour: Dictionary, ground: Callable, cfg: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if harbour.is_empty():
		return out
	var jetty := jetty_line(harbour, ground, cfg)
	var facing: Vector3 = jetty["facing"]
	var basis := Basis(Vector3.UP.cross(facing), Vector3.UP, facing)
	var right := facing.cross(Vector3.UP)
	var deck := float(jetty["deck"])
	var start: Vector3 = jetty["start"]
	# End to end in lengths the generator builds, as even as they divide; the ladder on the
	# last, and each one's piles down to the lowest ground under it.
	var sections := int(jetty["sections"])
	var parts := ceili(float(sections) / _param_range("sections").y)
	var from := 0
	for k in parts:
		var count := (sections * (k + 1)) / parts - (sections * k) / parts
		var a := start + facing * from * VoxJetty.SECTION
		var b := a + facing * count * VoxJetty.SECTION
		var height := _pile_height(a, b, deck, ground)
		var params: Dictionary = (cfg["jetty"]["params"] as Dictionary).duplicate()
		params["sections"] = float(count)
		params["height"] = height
		params["ladder"] = params.get("ladder", 1.0) if k == parts - 1 else 0.0
		params["seed"] = k + 1
		var middle := a.lerp(b, 0.5)
		out.append({"kind": "jetty", "generator": "VoxJetty", "params": params,
			"transform": Transform3D(basis, Vector3(middle.x, deck - height, middle.z))})
		from += count
	var anchors := {"shore": start, "end": start + facing * float(jetty["length"])}
	var sea := float((harbour["root"] as Vector3).y)
	var sink := float(cfg["sink"])
	var i := 0
	for piece: Dictionary in cfg["pieces"]:
		i += 1
		var at_list: Array = piece["at"]
		var anchor: Vector3 = anchors[str(piece["anchor"])]
		var at := anchor + right * float(at_list[0]) + facing * float(at_list[1])
		var turn := basis * Basis(Vector3.UP, deg_to_rad(float(piece["yaw"])))
		var p: Dictionary = (piece["params"] as Dictionary).duplicate()
		p["seed"] = i
		var y := sea - VoxBoat.WATERLINE
		if not bool(piece.get("afloat", false)):
			var place := Transform3D(turn, Vector3(at.x, 0.0, at.z))
			var foot := footprint(str(piece["generator"]), p)
			var low := lowest_under(place, foot, ground)
			# Set into the slope by its lowest corner, so on ground that rises too far across
			# it the uphill side would be buried: left out there.
			if highest_under(place, foot, ground) - low > float(cfg["max_rise"]):
				continue
			y = low - sink
		out.append({"kind": str(piece["name"]), "generator": str(piece["generator"]), "params": p, "transform": Transform3D(turn, Vector3(at.x, y, at.z))})
	return out


## Where the jetty runs: {start (its shore end, on the ground plane at the deck's height),
## facing (unit, out to sea), length (metres, whole sections), sections, deck (the deck's top),
## landed (whether the ground came within `step` of the deck within `landing` metres)}. The
## shore end is the first point in from the waterline where the ground stands no more than
## `step` under the deck; the sea end reaches at least the harbour's end.
static func jetty_line(harbour: Dictionary, ground: Callable, cfg: Dictionary) -> Dictionary:
	var j: Dictionary = cfg["jetty"]
	var root: Vector3 = harbour["root"]
	var facing: Vector3 = harbour["facing"]
	var deck := root.y + float(j["freeboard"])
	var step := float(j["step"])
	var landing := float(j["landing"])
	var start := root - facing * landing
	var landed := false
	var d := 0.0
	while d <= landing:
		var p := root - facing * d
		if float(ground.call(p.x, p.z)) >= deck - step:
			start = p
			landed = true
			break
		d += LANDING_STEP
	var reach := d + float(harbour["length"])
	var sections := ceili(reach / VoxJetty.SECTION - 0.001)
	var length := sections * VoxJetty.SECTION
	return {"start": Vector3(start.x, deck, start.z), "facing": facing, "length": length, "sections": sections, "deck": deck, "landed": landed}


## How tall a stretch of jetty from `a` to `b` stands, deck top over pile feet, for its piles
## to reach the lowest ground under it: within the generator's range for it.
static func _pile_height(a: Vector3, b: Vector3, deck: float, ground: Callable) -> float:
	var low := INF
	var length := a.distance_to(b)
	var k := 0.0
	while k <= length + 0.001:
		var p := a.lerp(b, k / length)
		low = minf(low, float(ground.call(p.x, p.z)))
		k += PILE_STEP
	var limits := _param_range("height")
	return clampf(deck - low, limits.x, limits.y)


## The jetty generator's own range for one of its parameters.
static func _param_range(key: String) -> Vector2:
	for p: Dictionary in VoxJetty.new().params():
		if p["key"] == key:
			return Vector2(float(p["min"]), float(p["max"]))
	return Vector2.ZERO


## The ground plan (x, z in model space) of what `generator` with `params` stands on: its
## collision boxes merged.
static func footprint(generator: String, params: Dictionary) -> Rect2:
	var gen := VoxCatalog.by_name(generator)
	var boxes: Array = gen.call(&"collision", params) if gen != null and gen.has_method(&"collision") else []
	if boxes.is_empty():
		return Rect2()
	var first: AABB = boxes[0]
	var out := Rect2(first.position.x, first.position.z, first.size.x, first.size.z)
	for box: AABB in boxes:
		out = out.merge(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))
	return out


## The lowest ground under the corners and middle of `foot` (model space) placed by `at`.
static func lowest_under(at: Transform3D, foot: Rect2, ground: Callable) -> float:
	var low := INF
	for c: Vector2 in [foot.position, Vector2(foot.end.x, foot.position.y), foot.end, Vector2(foot.position.x, foot.end.y), foot.get_center()]:
		var p := at * Vector3(c.x, 0.0, c.y)
		low = minf(low, float(ground.call(p.x, p.z)))
	return low


## The highest ground under the corners and middle of `foot` (model space) placed by `at`.
static func highest_under(at: Transform3D, foot: Rect2, ground: Callable) -> float:
	var high := -INF
	for c: Vector2 in [foot.position, Vector2(foot.end.x, foot.position.y), foot.end, Vector2(foot.position.x, foot.end.y), foot.get_center()]:
		var p := at * Vector3(c.x, 0.0, c.y)
		high = maxf(high, float(ground.call(p.x, p.z)))
	return high


## What is wrong with a harbour.json past its top-level fields: the jetty's fields, and each
## piece's (a generator the kit has, with collision boxes; an anchor; `at` as [x, z]; only a
## boat afloat), and no jetty params the plan sets itself. Empty when it is all right.
static func check(cfg: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if _has(cfg["jetty"], JETTY, "jetty", out):
		for key in PLANNED:
			if (cfg["jetty"]["params"] as Dictionary).has(key):
				out.append("jetty: `params` must not set `%s`, the plan does" % key)
	var pieces: Array = cfg["pieces"]
	for i in pieces.size():
		var where := "piece %d" % i
		var piece: Variant = pieces[i]
		if not piece is Dictionary:
			out.append("%s: not an object" % where)
			continue
		if not _has(piece, PIECE, where, out):
			continue
		var gen := VoxCatalog.by_name(str(piece["generator"]))
		if gen == null or not gen.has_method(&"collision"):
			out.append("%s: no voxel generator with collision named %s" % [where, piece["generator"]])
		if not ANCHORS.has(str(piece["anchor"])):
			out.append("%s: `anchor` must be one of %s" % [where, ANCHORS])
		if (piece["at"] as Array).size() != 2:
			out.append("%s: `at` must be [x, z]" % where)
		var afloat: Variant = (piece as Dictionary).get("afloat", false)
		# Only a boat knows where its waterline is.
		if not afloat is bool or (afloat and piece["generator"] != "VoxBoat"):
			out.append("%s: `afloat` must be true or false, and true only for a VoxBoat" % where)
	return out


static func _has(dict: Dictionary, fields: Dictionary, where: String, out: Array[String]) -> bool:
	var ok := true
	for field: String in fields:
		if not dict.has(field):
			out.append("%s: missing `%s`" % [where, field])
			ok = false
		elif typeof(dict[field]) != int(fields[field]):
			out.append("%s: `%s` should be %s" % [where, field, type_string(int(fields[field]))])
			ok = false
	return ok

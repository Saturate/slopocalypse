class_name SiteLayout
extends RefCounted
## Where each site's pieces stand (sites.json): the site turned so its front (-z) faces the
## side its track leaves by, then each piece at its offset, the layout maybe mirrored and the
## generator parameters picked, all from a seed made of the site's place. Pure; no autoloads.

const CONFIG := "res://modules/sites/data/sites.json"
const REQUIRED := {"kinds": TYPE_DICTIONARY, "sink": TYPE_FLOAT, "builds_per_frame": TYPE_FLOAT}
const KIND := {"pieces": TYPE_ARRAY}
const PIECE := {"generator": TYPE_STRING, "at": TYPE_ARRAY, "yaw": TYPE_FLOAT, "params": TYPE_DICTIONARY}


## What goes where: for every site whose kind has pieces, each piece as {kind, site (its
## place in `sites`), generator, params, transform}. `sites` is VoxelWorld.map_site_list's.
## Pure and seeded by the sites' places, so every machine plans the same.
static func plan(sites: Array, cfg: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var kinds: Dictionary = cfg["kinds"]
	var sink := float(cfg["sink"])
	for i in sites.size():
		var site: Dictionary = sites[i]
		var kind := str(site["kind"])
		if not kinds.has(kind):
			continue
		var layout: Dictionary = kinds[kind]
		var centre: Vector3 = site["centre"]
		var rng := _site_rng(kind, centre)
		var frame := Transform3D(Basis(Vector3.UP, site_yaw(site["toward"])), centre + Vector3.DOWN * sink)
		var mirror := _mirrored(layout, rng)
		for piece: Dictionary in layout.get("pieces", []):
			var local := piece_transform(piece, mirror)
			out.append({"kind": kind, "site": i, "generator": str(piece["generator"]), "params": piece_params(piece, rng), "transform": frame * local})
	return out


## Each site's yard (a kind's `yard` in sites.json): packed dirt from where its track
## arrives up to and between what stands there, as the world paints it into the ground
## (SceneryScatter `set_yards_for`): {site, from, to (x, z: the middles of its two ends),
## width, level}. Each rectangle of the layout is turned and mirrored with its site's pieces
## and cut to the footprint, so one reaching far towards the track ends at the pad's edge
## where the track comes in.
static func yards(sites: Array, cfg: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var kinds: Dictionary = cfg["kinds"]
	for i in sites.size():
		var site: Dictionary = sites[i]
		var kind := str(site["kind"])
		if not kinds.has(kind) or not (kinds[kind] as Dictionary).has("yard"):
			continue
		var layout: Dictionary = kinds[kind]
		var centre: Vector3 = site["centre"]
		var mirror := _mirrored(layout, _site_rng(kind, centre))
		var basis := Basis(Vector3.UP, site_yaw(site["toward"]))
		var foot: Rect2 = site["footprint"]
		for r: Array in layout["yard"]:
			var x0 := float(r[0])
			var x1 := float(r[2])
			if mirror:
				var flipped := -x0
				x0 = -x1
				x1 = flipped
			var a := centre + basis * Vector3(x0, 0.0, float(r[1]))
			var b := centre + basis * Vector3(x1, 0.0, float(r[3]))
			var rect := Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)).intersection(foot)
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				continue
			# Along the site's front-to-back axis, whichever world axis that is.
			var along_x := absf(basis.z.x) > 0.5
			var mid := rect.get_center()
			var from := Vector2(rect.position.x, mid.y) if along_x else Vector2(mid.x, rect.position.y)
			var to := Vector2(rect.end.x, mid.y) if along_x else Vector2(mid.x, rect.end.y)
			out.append({"site": i, "from": from, "to": to, "width": rect.size.y if along_x else rect.size.x, "level": centre.y, "rect": rect})
	return out


static func _site_rng(kind: String, centre: Vector3) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([kind, roundi(centre.x * 10.0), roundi(centre.z * 10.0)])
	return rng


## Whether the site's layout is flipped left to right: the first draw of its seed.
static func _mirrored(layout: Dictionary, rng: RandomNumberGenerator) -> bool:
	return bool(layout.get("mirror", false)) and rng.randf() < 0.5


## The yaw that turns a site's front (-z) toward `toward` (the side its track leaves by).
static func site_yaw(toward: Vector3) -> float:
	return atan2(-toward.x, -toward.z)


## A piece's place in its site's frame, flipped left to right when `mirror`.
static func piece_transform(piece: Dictionary, mirror: bool) -> Transform3D:
	var at_list: Array = piece["at"]
	var at := Vector3(float(at_list[0]), float(at_list[1]), float(at_list[2]))
	var yaw := deg_to_rad(float(piece["yaw"]))
	if mirror:
		at.x = -at.x
		yaw = -yaw
	return Transform3D(Basis(Vector3.UP, yaw), at)


## A piece's generator parameters: its own, then the seed's picks from its choices and ranges,
## and a generator seed of its own.
static func piece_params(piece: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var params: Dictionary = (piece.get("params", {}) as Dictionary).duplicate()
	var choices: Dictionary = piece.get("choices", {})
	for key: String in choices:
		var options: Array = choices[key]
		params[key] = options[rng.randi_range(0, options.size() - 1)]
	var ranges: Dictionary = piece.get("ranges", {})
	for key: String in ranges:
		var span: Array = ranges[key]
		params[key] = rng.randf_range(float(span[0]), float(span[1]))
	params["seed"] = rng.randi_range(0, 9999)
	return params


## What is wrong with a sites.json past its top-level fields: each kind needs its `pieces`,
## each piece its `generator` (one the kit has), `at` ([x, y, z]), `yaw` and `params`.
## Empty when it is all right.
static func check(cfg: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var kinds: Dictionary = cfg["kinds"]
	for kind: String in kinds:
		var layout: Variant = kinds[kind]
		if not (layout is Dictionary and _has(layout, KIND, "%s" % kind, out)):
			if not layout is Dictionary:
				out.append("%s: not an object" % kind)
			continue
		var pieces: Array = (layout as Dictionary)["pieces"]
		for i in pieces.size():
			var where := "%s piece %d" % [kind, i]
			var piece: Variant = pieces[i]
			if not piece is Dictionary:
				out.append("%s: not an object" % where)
				continue
			if not _has(piece, PIECE, where, out):
				continue
			if VoxCatalog.by_name(str(piece["generator"])) == null:
				out.append("%s: no voxel generator named %s" % [where, piece["generator"]])
			if (piece["at"] as Array).size() != 3:
				out.append("%s: `at` must be [x, y, z]" % where)
		var yard: Variant = (layout as Dictionary).get("yard", [])
		if not yard is Array or not (yard as Array).all(func(r: Variant) -> bool: return r is Array and (r as Array).size() == 4 and (r as Array).all(func(v: Variant) -> bool: return v is float or v is int)):
			out.append("%s: `yard` must be a list of [x0, z0, x1, z1]" % kind)
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

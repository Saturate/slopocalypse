class_name MissionLayout
extends RefCounted
## Where a mission zone's buildings stand: round the place the mission goes to (a map site,
## or a roadside spot), off its pad, apart from each other, doors toward its middle and square
## to its sides. Pure: the same seed and place give the same layout on every machine.

## `cfg` is the `buildings` block of missions.json; `place` is MissionSites' {centre,
## footprint (Rect2 on x, z; empty for a roadside spot), toward (the way its track leaves)}.
## Each building stands `off_site` metres out from the footprint's edge. Returns layout
## entries `{position, yaw, width, depth, wall_height, windows, paint, seed}`; `position` is
## on the place's level, the caller puts it on the ground. `blocked(at, radius) -> bool`
## turns down a spot someone else holds (the site's own pad and yard, another site, a road,
## the city, water), so the buildings go up beside it instead.
static func buildings(cfg: Dictionary, seed_value: int, place: Dictionary, blocked := Callable()) -> Array:
	if cfg.get("row") is Array:
		return row(cfg, place)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var count_range: Array = cfg.get("count", [3, 6])
	var count := rng.randi_range(int(count_range[0]), int(count_range[1]))
	var width: Array = cfg.get("width", [5.0, 8.0])
	var depth: Array = cfg.get("depth", [4.0, 6.0])
	var height: Array = cfg.get("wall_height", [2.7, 3.2])
	var off: Array = cfg.get("off_site", [4.0, 18.0])
	var gap := float(cfg.get("gap", 3.0))
	var foot: Rect2 = place["footprint"]
	var centre: Vector3 = place["centre"]
	var middle := Vector3(foot.get_center().x, centre.y, foot.get_center().y)
	var frame := atan2(-(place["toward"] as Vector3).x, -(place["toward"] as Vector3).z)
	var out := []
	var tries := 0
	while out.size() < count and tries < count * 40:
		tries += 1
		var w := snappedf(rng.randf_range(float(width[0]), float(width[1])), 0.25)
		var d := snappedf(rng.randf_range(float(depth[0]), float(depth[1])), 0.25)
		var angle := rng.randf() * TAU
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var radius := Vector2(w, d).length() / 2.0
		# Out to the footprint grown by the offset and the building's own reach, so every
		# side of it keeps at least the offset from the pad, corners included.
		var at := middle + dir * MissionSites.edge(foot.grow(rng.randf_range(float(off[0]), float(off[1])) + radius), dir)
		if blocked.is_valid() and bool(blocked.call(at, radius)):
			continue
		var clear := true
		for other: Dictionary in out:
			var o: Vector3 = other["position"]
			if Vector2(at.x - o.x, at.z - o.z).length() < radius + float(other["radius"]) + gap:
				clear = false
				break
		if not clear:
			continue
		# The door (local -Z) toward the middle, turned square to the site's own sides.
		var facing := atan2(dir.x, dir.z)
		out.append({
			"position": at,
			"yaw": frame + snappedf(angle_difference(frame, facing), PI / 2.0),
			"width": w, "depth": d,
			"wall_height": snappedf(rng.randf_range(float(height[0]), float(height[1])), 0.1),
			"windows": rng.randi_range(1, 4),
			"paint": rng.randi_range(0, 3),
			"seed": rng.randi(),
			"radius": radius,
			"material": str(cfg["material"]) if cfg.has("material") else ("concrete" if rng.randf() < float(cfg.get("concrete_share", 0.0)) else "wood"),
		})
	return out


## A fixed row instead of a rolled layout (the test range): `cfg.row` lists the buildings in
## order, each `{material, glass?, width?, depth?, wall_height?, windows?, paint?}`, side by
## side `gap` apart across `place`'s centre, their doors on the line through it and facing
## `toward` (the road), with `row_clear` metres of open ground round each.
static func row(cfg: Dictionary, place: Dictionary) -> Array:
	var gap := float(cfg.get("gap", 3.0))
	var centre: Vector3 = place["centre"]
	var toward: Vector3 = place["toward"]
	var across := Vector3(-toward.z, 0.0, toward.x)
	var yaw := atan2(-toward.x, -toward.z)
	var out := []
	var entries: Array = cfg["row"]
	var total := 0.0
	for e: Dictionary in entries:
		total += float(e.get("width", 5.0)) + gap
	var cursor := -total / 2.0
	for i in entries.size():
		var e: Dictionary = entries[i]
		var w := float(e.get("width", 5.0))
		var d := float(e.get("depth", 4.0))
		var at := centre + across * (cursor + w / 2.0) - toward * (d / 2.0)
		cursor += w + gap
		out.append({
			"position": at,
			"yaw": yaw,
			"width": w, "depth": d,
			"wall_height": float(e.get("wall_height", 2.8)),
			"windows": int(e.get("windows", 2)),
			"paint": int(e.get("paint", 1)),
			"seed": 1000 + i,
			"radius": Vector2(w, d).length() / 2.0,
			"material": str(e.get("material", "wood")),
			"glass": str(e.get("glass", "window_glass")),
			"clear": float(cfg.get("row_clear", 3.0)),
		})
		# Anything else the row gives (a wall sample's kind, label, window, door) goes along.
		for key: String in e:
			if not (out[-1] as Dictionary).has(key):
				out[-1][key] = e[key]
	return out

class_name MissionLayout
extends RefCounted
## Where a mission zone's buildings stand: along the road on both sides, off the road, apart
## from each other, doors facing the road. Pure: the same seed and road give the same
## layout on every machine.

## `cfg` is the `buildings` block of missions.json; `road_at` maps metres along the road to
## a point on it; `along` is where the zone's centre is on the road. Returns layout entries
## `{position, yaw, width, depth, wall_height, windows, paint, seed}`; `position` is on the
## road's level, the caller puts it on the ground.
static func buildings(cfg: Dictionary, seed_value: int, road_at: Callable, along: float) -> Array:
	if cfg.get("row") is Array:
		return row(cfg, road_at, along)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var count_range: Array = cfg.get("count", [3, 6])
	var count := rng.randi_range(int(count_range[0]), int(count_range[1]))
	var width: Array = cfg.get("width", [5.0, 8.0])
	var depth: Array = cfg.get("depth", [4.0, 6.0])
	var height: Array = cfg.get("wall_height", [2.7, 3.2])
	var off: Array = cfg.get("off_road", [9.0, 24.0])
	var spread := float(cfg.get("spread", 35.0))
	var gap := float(cfg.get("gap", 3.0))
	var out := []
	var tries := 0
	while out.size() < count and tries < count * 20:
		tries += 1
		var w := snappedf(rng.randf_range(float(width[0]), float(width[1])), 0.25)
		var d := snappedf(rng.randf_range(float(depth[0]), float(depth[1])), 0.25)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var on_road: Vector3 = road_at.call(along + rng.randf_range(-spread, spread))
		var lateral := rng.randf_range(float(off[0]), float(off[1])) + d / 2.0
		var at := on_road + Vector3(side * lateral, 0.0, 0.0)
		var radius := Vector2(w, d).length() / 2.0
		var clear := true
		for other: Dictionary in out:
			var o: Vector3 = other["position"]
			if Vector2(at.x - o.x, at.z - o.z).length() < radius + float(other["radius"]) + gap:
				clear = false
				break
		if not clear:
			continue
		out.append({
			"position": at,
			# The door (local -Z) faces the road: towards -x on the +x side and the other way.
			"yaw": side * PI / 2.0,
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
## order, each `{material, glass?, width?, depth?, wall_height?, windows?, paint?}`, standing
## `row_off_road` metres off the road on the +x side, `gap` apart, doors facing the road, with
## `row_clear` metres of open ground round each (no trees between them and the road).
static func row(cfg: Dictionary, road_at: Callable, along: float) -> Array:
	var gap := float(cfg.get("gap", 3.0))
	var off := float(cfg.get("row_off_road", 12.0))
	var out := []
	var entries: Array = cfg["row"]
	var total := 0.0
	for e: Dictionary in entries:
		total += float(e.get("width", 5.0)) + gap
	var cursor := along - total / 2.0
	for i in entries.size():
		var e: Dictionary = entries[i]
		var w := float(e.get("width", 5.0))
		var d := float(e.get("depth", 4.0))
		var on_road: Vector3 = road_at.call(cursor + w / 2.0)
		cursor += w + gap
		out.append({
			"position": on_road + Vector3(off + d / 2.0, 0.0, 0.0),
			"yaw": PI / 2.0,
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

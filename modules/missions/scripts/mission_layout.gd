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
		})
	return out

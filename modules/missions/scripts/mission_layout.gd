class_name MissionLayout
extends RefCounted
## Where a mission zone's buildings stand: round the place the mission goes to (a map site,
## or a roadside spot), off its pad, apart from each other, doors toward its middle and square
## to its sides. Pure: the same seed and place give the same layout on every machine.

## `cfg` is the `buildings` block of missions.json; `place` is MissionSites' {centre,
## footprint (Rect2 on x, z; empty for a roadside spot), toward (the way its track leaves)}.
## Each building stands `off_site` metres out from the footprint's edge (`off_roadside`
## from a roadside spot's centre). Returns layout
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
	var gap := float(cfg.get("gap", 3.0))
	var foot: Rect2 = place["footprint"]
	# Round a roadside spot (no pad) they keep further apart: nothing there ties them together.
	var off: Array = cfg.get("off_site", [4.0, 18.0]) if foot.has_area() else cfg.get("off_roadside", cfg.get("off_site", [4.0, 18.0]))
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


## The fence round a mission at a map site, so the site and the buildings round it read as
## one guarded place: a rectangle `cfg.margin` metres out from the site's footprint and every
## building in `entries`, each side cut into as few equal runs as keep them within
## `cfg.segment` metres (so a side's runs are alike and share one mesh). The runs where
## the ray from the footprint's middle along `place.toward` (the way its track leaves) meets
## the fence are left out, `cfg.gate` metres wide, its two leaves (`gate_leaf` metres long,
## `gate`: true) standing open `gate_swing` degrees outward from the posts either side; so
## is every run or leaf `blocked(at, cfg.post_clear) -> bool` turns down anywhere along it
## (a road or track, water, another site), and a share
## `cfg.gaps` of the rest, rolled from `seed_value` (never a side's end runs, so the corners
## stand). Returns `{from, to (on the place's level; the caller puts them on the ground),
## tall_ends (the run starts or ends a side or a stretch: corner and gate posts)}`, in order
## round the fence. A roadside spot (an empty footprint) gets none.
static func fence(cfg: Dictionary, place: Dictionary, entries: Array, seed_value: int, blocked := Callable()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var foot: Rect2 = place["footprint"]
	if foot.size.x <= 0.0 or foot.size.y <= 0.0:
		return out
	var bounds := foot
	for e: Dictionary in entries:
		var at: Vector3 = e["position"]
		var basis := Basis(Vector3.UP, float(e["yaw"]))
		var half := Vector3(float(e["width"]) / 2.0, 0.0, float(e["depth"]) / 2.0)
		for corner: Vector3 in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
			var p := at + basis * (corner * half)
			bounds = bounds.expand(Vector2(p.x, p.z))
	bounds = bounds.grow(float(cfg["margin"]))
	var step := float(cfg["segment"])
	var toward: Vector3 = place["toward"]
	var gate_at := _exit(bounds, foot.get_center(), Vector2(toward.x, toward.z))
	var gate_half := float(cfg["gate"]) / 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var gaps := float(cfg.get("gaps", 0.0))
	var clear := float(cfg.get("post_clear", 0.3))
	var level := (place["centre"] as Vector3).y
	var corners: Array[Vector2] = [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]
	for side in 4:
		var a := corners[side]
		var b := corners[(side + 1) % 4]
		var n := ceili(a.distance_to(b) / step - 0.001)
		var keep: Array[bool] = []
		var gate_runs: Array[int] = []
		for k in n:
			var ra := a.lerp(b, float(k) / n)
			var rb := a.lerp(b, float(k + 1) / n)
			var ok := Geometry2D.get_closest_point_to_segment(gate_at, ra, rb).distance_to(gate_at) >= gate_half
			if not ok:
				gate_runs.append(k)
			ok = ok and not _run_blocked(ra, rb, level, clear, blocked)
			# Every run draws, so one blocked run never shifts which others break.
			var broken := rng.randf() < gaps
			keep.append(ok and (k == 0 or k == n - 1 or not broken))
		for k in n:
			if not keep[k]:
				continue
			var ra := a.lerp(b, float(k) / n)
			var rb := a.lerp(b, float(k + 1) / n)
			var ends := k == 0 or k == n - 1 or not keep[k - 1] or not keep[k + 1]
			out.append({"from": Vector3(ra.x, level, ra.y), "to": Vector3(rb.x, level, rb.y), "tall_ends": ends})
		if gate_runs.is_empty():
			continue
		# The gate's two leaves, hinged on the posts either side of it and swung out.
		var along := (b - a).normalized()
		var outward := Vector2(-along.y, along.x)
		if outward.dot((a + b) / 2.0 - bounds.get_center()) < 0.0:
			outward = -outward
		var swing := deg_to_rad(float(cfg.get("gate_swing", 70.0)))
		var leaf := float(cfg.get("gate_leaf", 2.4))
		for hinge_side: Array in [[a.lerp(b, float(gate_runs[0]) / n), along], [a.lerp(b, float(gate_runs[-1] + 1) / n), -along]]:
			var hinge: Vector2 = hinge_side[0]
			var shut: Vector2 = hinge_side[1]
			var tip := hinge + (shut * cos(swing) + outward * sin(swing)) * leaf
			if not _run_blocked(hinge, tip, level, clear, blocked):
				out.append({"from": Vector3(hinge.x, level, hinge.y), "to": Vector3(tip.x, level, tip.y), "tall_ends": true, "gate": true})
	return out


## Whether a run from `a` to `b` is turned down: `blocked` asked every metre or so along it
## (a road beside a run but clear of it leaves it standing; one across it does not).
static func _run_blocked(a: Vector2, b: Vector2, level: float, radius: float, blocked: Callable) -> bool:
	if not blocked.is_valid():
		return false
	var steps := maxi(ceili(a.distance_to(b)), 1)
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		if bool(blocked.call(Vector3(p.x, level, p.y), radius)):
			return true
	return false


## Where the ray from `from` (inside `rect`) along `dir` leaves it.
static func _exit(rect: Rect2, from: Vector2, dir: Vector2) -> Vector2:
	var t := INF
	if absf(dir.x) > 0.0001:
		t = minf(t, ((rect.end.x if dir.x > 0.0 else rect.position.x) - from.x) / dir.x)
	if absf(dir.y) > 0.0001:
		t = minf(t, ((rect.end.y if dir.y > 0.0 else rect.position.y) - from.y) / dir.y)
	return from + dir * (t if t < INF else 0.0)


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

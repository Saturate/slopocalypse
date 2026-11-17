class_name CityGuards
extends RefCounted
## Where the city's guards stand (#220), worked out from its plan (CityLayout), in city
## metres: behind street-facing windows on upper floors looking out, on flat roofs at the
## street edge, on the pavement at block corners looking out across the junction, and
## routes round blocks on the pavement for patrols. Pure and seeded; the server spawns
## guards on them (CityGarrison).

## How far behind the outer wall's face a window post stands, and inside a corner a pavement
## post stands.
const BEHIND_WINDOW := 1.0
const CORNER_INSET := 1.4
const ROUTE_INSET := 1.5


## `counts`: window_posts, roof_posts, corner_posts, patrols. Returns {windows, roofs,
## corners: Array of {at: Vector3, yaw, building (for windows and roofs)}, routes: Array of
## Array[Vector3]}. Roof posts' `at.y` is the eaves; the server sets them on the roof it finds.
static func spots(plan: Dictionary, counts: Dictionary, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var gen := VoxApartment.new()
	var windows: Array[Dictionary] = []
	var roofs: Array[Dictionary] = []
	for b: Dictionary in plan["buildings"]:
		var p := gen.with_defaults(b["params"])
		var layout := gen.layout(p)
		var basis := Basis(Vector3.UP, float(b["yaw"]))
		var centre := (b["footprint"] as Rect2).get_center()
		var place := func(local: Vector3) -> Vector3:
			return Vector3(centre.x, CitySite.KERB, centre.y) + basis * local
		var depth := float(layout["depth"])
		var wall := float(layout["wall"])
		var levels: Array = layout["levels"]
		var count := int(p["windows"])
		for f: int in (layout["flats"] as Array).size():
			var flat: Vector2 = layout["flats"][f]
			for k in count:
				for li in range(1, levels.size()):
					windows.append({"at": place.call(Vector3(VoxApartment.window_x(flat, count, k), float(levels[li]), -depth / 2.0 + wall + BEHIND_WINDOW)), "yaw": float(b["yaw"]), "building": b})
		if int(p["roof"]) == 2:
			roofs.append({"at": place.call(Vector3(0.0, float(layout["eaves"]), -depth / 2.0 + 1.5)), "yaw": float(b["yaw"]), "building": b})
	var corners: Array[Dictionary] = []
	var routes: Array[Array] = []
	var squares: Array = plan["squares"]
	for block: Rect2 in plan["blocks"]:
		var c := block.get_center()
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var at := Vector2(c.x + sx * (block.size.x / 2.0 - CORNER_INSET), c.y + sz * (block.size.y / 2.0 - CORNER_INSET))
				var out := Vector2(sx, sz).normalized()
				corners.append({"at": Vector3(at.x, CitySite.KERB, at.y), "yaw": atan2(-out.x, -out.y)})
		if not squares.has(block):
			var r := block.grow(-ROUTE_INSET)
			routes.append([
				Vector3(r.position.x, CitySite.KERB, r.position.y), Vector3(r.end.x, CitySite.KERB, r.position.y),
				Vector3(r.end.x, CitySite.KERB, r.end.y), Vector3(r.position.x, CitySite.KERB, r.end.y),
			])
	return {
		"windows": _pick(windows, int(counts.get("window_posts", 0)), rng),
		"roofs": _pick(roofs, int(counts.get("roof_posts", 0)), rng),
		"corners": _pick(corners, int(counts.get("corner_posts", 0)), rng),
		"routes": _pick(routes, int(counts.get("patrols", 0)), rng),
	}


## `n` of `from`, chosen by the seed, in a fixed order.
static func _pick(from: Array, n: int, rng: RandomNumberGenerator) -> Array:
	var pool := from.duplicate()
	var out: Array = []
	while out.size() < n and not pool.is_empty():
		out.append(pool.pop_at(rng.randi() % pool.size()))
	return out

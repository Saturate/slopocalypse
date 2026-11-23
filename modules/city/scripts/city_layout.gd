class_name CityLayout
extends RefCounted
## The plan of a European city, in metres on its own ground (x and z centred on the city, -z
## toward the road it joins). Streets ring it and cross it, each line nudged up to
## `street_jitter` off a regular grid so blocks differ; the inner lines are wider avenues.
## Each block is a perimeter block: a pavement round it, one building along each side with
## its front on the street (the two street fronts run corner to corner, the sides butt
## against them), a courtyard in the middle, and a gateway through the ground floor of each
## street front into it. The middle block of an odd grid is left open as a square. A little
## taller toward the middle. Along the streets: zebra crossings by every junction between
## blocks, street lamps on both sides, trees on the avenues, all clear of doors, gateways
## and crossings. Pure and seeded, so every machine builds the same city.

const STAIR_BAY := 3.0
const FLAT_MIN := 4.5
## The shortest building that fits: one stairwell with a flat each side.
const SHORTEST := FLAT_MIN * 2.0 + STAIR_BAY
## The shallowest apartment block (VoxApartment's depth range). A street front gives up depth
## down to this so the side buildings between the two fronts still fit.
const DEPTH_MIN := 8.0
## Per style, the apartment block's wall and roof choices to pick from (VoxApartment.WALLS,
## ROOFS): yellow and red brick, white, pale grey and ochre render.
const STYLES := {
	"danish": {"walls": [0, 1, 3, 4, 5], "roof": [0, 0, 1]},
}
## The four ways a block edge can face, out toward its street.
const SIDES: Array[Vector2] = [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]


## `cfg`: city.json. Returns {streets, blocks, squares, passages, yards, crossings:
## Array[Rect2], buildings: Array of {footprint: Rect2, facing: Vector2, yaw, doors:
## Array[Vector2] (a step out of each front door), door_out (the first of them), params},
## lamps: Array of {at: Vector2, out: Vector2 (toward the street)}, trees: Array[Vector2]}.
## `handmade`: the hand-made blocks to choose from (#339), each {name, size: Vector2, tags,
## markers}; a placed one replaces the block's generated buildings and is listed under
## `handmade` as {name, rect, centre, yaw, markers (in city metres)}.
static func make(cfg: Dictionary, seed: int, handmade: Array = []) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var size := float(cfg["size"])
	var n := int(cfg["blocks"])
	var street := float(cfg["street_width"])
	var avenue := float(cfg.get("avenue_width", street))
	var jitter := float(cfg["street_jitter"])
	var pave := float(cfg["pavement"])
	var depth := float(cfg["building_depth"])
	var style: Dictionary = STYLES.get(str(cfg.get("style", "danish")), STYLES["danish"])
	var half := size / 2.0
	var widths: Array[float] = []
	var total := 0.0
	for i in n + 1:
		widths.append(street if i == 0 or i == n else avenue)
		total += widths[i]
	var pitch := (size - total) / n
	# Where each street line starts, across x and across z; the outer ones stay put.
	var lines: Array[Array] = [[], []]
	for axis in 2:
		var at := -half
		for i in n + 1:
			var nudge := rng.randf_range(-jitter, jitter) if i > 0 and i < n else 0.0
			lines[axis].append(at + nudge)
			at += widths[i] + pitch
	var streets: Array[Rect2] = []
	for i in n + 1:
		streets.append(Rect2(float(lines[0][i]), -half, widths[i], size))
		streets.append(Rect2(-half, float(lines[1][i]), size, widths[i]))
	var blocks: Array[Rect2] = []
	var squares: Array[Rect2] = []
	var passages: Array[Rect2] = []
	var yards: Array[Rect2] = []
	var buildings: Array[Dictionary] = []
	var placed: Array[Dictionary] = []
	## Grid cell -> the hand-made block placed there, so neighbours never repeat.
	var taken: Dictionary[Vector2i, String] = {}
	for bx in n:
		for bz in n:
			var x0 := float(lines[0][bx]) + widths[bx]
			var z0 := float(lines[1][bz]) + widths[bz]
			var block := Rect2(x0, z0, float(lines[0][bx + 1]) - x0, float(lines[1][bz + 1]) - z0)
			blocks.append(block)
			var is_square := n % 2 == 1 and bx == n / 2 and bz == n / 2
			if is_square:
				squares.append(block)
			if not handmade.is_empty():
				var chosen := _choose_handmade(block.grow(-pave), is_square, handmade, cfg, rng, taken, Vector2i(bx, bz))
				if not chosen.is_empty():
					placed.append(chosen)
					taken[Vector2i(bx, bz)] = chosen["name"]
					continue
			if is_square:
				continue
			var inner := block.grow(-pave)
			var front := clampf((inner.size.y - SHORTEST) / 2.0, DEPTH_MIN, depth)
			yards.append(Rect2(inner.position.x + depth, inner.position.y + front, inner.size.x - depth * 2.0, inner.size.y - front * 2.0))
			for row in [-1, 1]:
				var zr := inner.position.y if row == -1 else inner.end.y - front
				var foot := Rect2(inner.position.x, zr, inner.size.x, front)
				if foot.size.x >= SHORTEST:
					var b := _building(foot, Vector2(0, row), size, cfg, style, rng, true)
					buildings.append(b)
					if b.has("gateway"):
						passages.append(b["gateway"])
			for col in [-1, 1]:
				var xc := inner.position.x if col == -1 else inner.end.x - depth
				var foot := Rect2(xc, inner.position.y + front, depth, inner.size.y - front * 2.0)
				if foot.size.y >= SHORTEST:
					buildings.append(_building(foot, Vector2(col, 0), size, cfg, style, rng, false))
	_colour_walls(buildings, style["walls"], maxf(street, avenue) + pave * 2.0 + 0.5, rng)
	var crossings := _crossings(lines, widths, n, cfg)
	var keep: Array[Rect2] = []
	var door_clear := float(cfg.get("door_clear", 2.0))
	for b in buildings:
		for door: Vector2 in b["doors"]:
			keep.append(Rect2(door - Vector2.ONE * door_clear, Vector2.ONE * door_clear * 2.0))
	for passage in passages:
		keep.append(passage.grow(pave + 1.0))
	for c in crossings:
		keep.append(c.grow(pave + 1.0))
	for h in placed:
		for m: Dictionary in h["markers"]:
			if m["kind"] == "door" or m["kind"] == "passage":
				var at: Vector3 = m["at"]
				keep.append(Rect2(Vector2(at.x, at.z) - Vector2.ONE * door_clear, Vector2.ONE * door_clear * 2.0))
	var lamps: Array[Dictionary] = []
	var trees: Array[Vector2] = []
	var corner := float(cfg.get("crossing_setback", 0.6)) + float(cfg.get("crossing_width", 3.0)) + 1.0
	var nudge := float(cfg.get("spot_nudge", 3.0))
	var lamp_spacing := float(cfg.get("lamp_spacing", 25.0))
	var tree_spacing := float(cfg.get("tree_spacing", 12.0))
	var tree_street := float(cfg.get("tree_street_width", avenue))
	for i in blocks.size():
		var block := blocks[i]
		var bx := i / n
		var bz := i % n
		for out in SIDES:
			var on_edge := _edge_spots(block, out, lamp_spacing, float(cfg.get("lamp_inset", 0.5)), corner, -half, keep, nudge, [], 0.0)
			for at in on_edge:
				lamps.append({"at": at, "out": out})
			# The street this edge faces: its line, by which way the edge looks.
			var line := (bx + (1 if out.x > 0.0 else 0)) if out.x != 0.0 else (bz + (1 if out.y > 0.0 else 0))
			if widths[line] >= tree_street - 0.001:
				trees.append_array(_edge_spots(block, out, tree_spacing, float(cfg.get("tree_inset", 1.1)), corner, -half, keep, nudge, on_edge, 2.5))
	return {
		"streets": streets, "blocks": blocks, "squares": squares, "passages": passages, "yards": yards, "handmade": placed,
		"buildings": buildings, "crossings": crossings, "lamps": lamps, "trees": trees, "lines": lines, "widths": widths,
	}


## An apartment block filling `foot`, its front toward `facing`; a street front gets a
## gateway through its ground floor if it is long enough for two stairwells.
static func _building(foot: Rect2, facing: Vector2, size: float, cfg: Dictionary, style: Dictionary, rng: RandomNumberGenerator, gateway: bool) -> Dictionary:
	var length := maxf(foot.size.x, foot.size.y)
	var depth := minf(foot.size.x, foot.size.y)
	# As many stairwells as fit, and flats exactly as wide as fills the plot: wall to wall
	# with the neighbours, no gaps along the street.
	var stairwells := maxi(1, floori(length / SHORTEST))
	var flat := maxf((length / stairwells - STAIR_BAY) / 2.0, FLAT_MIN)
	var out := clampf(foot.get_center().length() / (size * 0.55), 0.0, 1.0)
	var floors := clampi(roundi(lerpf(float(cfg["floors_middle"]), float(cfg["floors_edge"]), out)) + rng.randi_range(-1, 0), 3, 6)
	var centre := foot.get_center()
	var roofs: Array = style["roof"]
	# The apartment's front is -Z; turned to face its street.
	var yaw := atan2(-facing.x, -facing.y) if facing != Vector2(0, -1) else 0.0
	var basis := Basis(Vector3.UP, yaw)
	var to_plan := func(x: float, z: float) -> Vector2:
		var w := basis * Vector3(x, 0.0, z)
		return centre + Vector2(w.x, w.z)
	var params := {
		"floors": float(floors), "stairwells": float(stairwells), "flat_width": flat, "depth": depth,
		"walls": 0.0, "roof": float(roofs[rng.randi() % roofs.size()]),
		# A raised ground floor over a basement, as in the blocks it copies; it also leaves a
		# full-height gateway under the first floor.
		"basement": 1.0, "balconies": 1.0, "balcony_sides": 0.0, "interior": 1.0, "elevators": 0.0,
		"seed": float(rng.randi_range(1, 99999)),
	}
	var section := flat * 2.0 + STAIR_BAY
	var doors: Array[Vector2] = []
	for s in stairwells:
		doors.append(to_plan.call(-length / 2.0 + s * section + flat + STAIR_BAY / 2.0, -depth / 2.0 - 1.0))
	if gateway:
		# French balconies, flush with the wall: a street front's courtyard side has the side
		# buildings butting against both its ends, where balconies standing out would cut in.
		params["balconies"] = 3.0
	var b := {"footprint": foot, "facing": facing, "yaw": yaw, "doors": doors, "door_out": doors[0], "params": params}
	if gateway and stairwells >= 2:
		var width := float(cfg["passage_width"])
		params.merge({"gateway": 1.0, "gateway_at": float(stairwells / 2), "gateway_width": width, "gateway_height": float(cfg.get("gateway_height", 3.2))})
		var gx := VoxApartment.gateway_x(params)
		var a: Vector2 = to_plan.call(gx - width / 2.0, -depth / 2.0)
		var c: Vector2 = to_plan.call(gx + width / 2.0, depth / 2.0)
		b["gateway"] = Rect2(Vector2(minf(a.x, c.x), minf(a.y, c.y)), (a - c).abs())
	return b


## Wall finishes so no two buildings that touch, and no two fronts next to each other along
## the same side of a street (`gap` apart at most), share a colour.
static func _colour_walls(buildings: Array[Dictionary], palette: Array, gap: float, rng: RandomNumberGenerator) -> void:
	for i in buildings.size():
		var a := buildings[i]
		var taken := {}
		for j in i:
			var b := buildings[j]
			var fa: Rect2 = a["footprint"]
			var fb: Rect2 = b["footprint"]
			if fa.grow(0.05).intersects(fb) or (a["facing"] == b["facing"] and fa.grow(gap / 2.0).intersects(fb.grow(gap / 2.0))):
				taken[int((b["params"] as Dictionary)["walls"])] = true
		var options := palette.duplicate()
		# Shuffled by the city's own generator, so every machine picks the same.
		for k in range(options.size() - 1, 0, -1):
			var swap := rng.randi_range(0, k)
			var keep: Variant = options[k]
			options[k] = options[swap]
			options[swap] = keep
		var pick: int = options[0]
		for option: int in options:
			if not taken.has(option):
				pick = option
				break
		(a["params"] as Dictionary)["walls"] = float(pick)


## A crossing just off every junction on each street that has blocks on both sides (not the
## ring at the city's edge), on each arm that leads between two blocks.
static func _crossings(lines: Array[Array], widths: Array[float], n: int, cfg: Dictionary) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var setback := float(cfg.get("crossing_setback", 0.6))
	var length := float(cfg.get("crossing_width", 3.0))
	for axis in 2:
		var across := 1 - axis
		for i in range(1, n):
			var at := float(lines[axis][i])
			for k in n + 1:
				var j0 := float(lines[across][k])
				for dir in [-1, 1]:
					if (dir == -1 and k == 0) or (dir == 1 and k == n):
						continue
					var along := j0 + widths[k] + setback if dir == 1 else j0 - setback - length
					out.append(Rect2(at, along, widths[i], length) if axis == 0 else Rect2(along, at, length, widths[i]))
	return out


## Spots along one edge of `block` (facing `out`), `inset` in from the kerb, every `spacing`
## metres on a grid from `origin` that is half a step out of phase on the far side of each
## street, so the two sides alternate. A spot inside a `keep` rectangle, or nearer than
## `avoid_r` to an `avoid` point, is nudged along by up to `nudge` metres or left out.
static func _edge_spots(block: Rect2, out: Vector2, spacing: float, inset: float, corner: float, origin: float, keep: Array[Rect2], nudge: float, avoid: Array[Vector2], avoid_r: float) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	var along_x := out.x == 0.0
	var a0 := (block.position.x if along_x else block.position.y) + corner
	var a1 := (block.end.x if along_x else block.end.y) - corner
	var fixed: float
	if along_x:
		fixed = block.position.y + inset if out.y < 0.0 else block.end.y - inset
	else:
		fixed = block.position.x + inset if out.x < 0.0 else block.end.x - inset
	var phase := origin + (0.0 if out.x + out.y < 0.0 else spacing / 2.0)
	var c := phase + ceilf((a0 - phase) / spacing) * spacing
	var shifts: Array[float] = [0.0]
	for s in range(1, floori(nudge) + 1):
		shifts.append_array([float(s), -float(s)])
	while c <= a1 + 0.001:
		for shift in shifts:
			var t := c + shift
			if t < a0 or t > a1:
				continue
			var p := Vector2(t, fixed) if along_x else Vector2(fixed, t)
			if _clear(p, keep, avoid, avoid_r):
				spots.append(p)
				break
		c += spacing
	return spots


static func _clear(p: Vector2, keep: Array[Rect2], avoid: Array[Vector2], avoid_r: float) -> bool:
	for r in keep:
		if r.has_point(p):
			return false
	for a in avoid:
		if a.distance_to(p) < avoid_r:
			return false
	return true


## A hand-made block for the plot `inner` (inside its pavement), or empty: the square always
## takes a square block that fits; other plots take one with chance `handmade_share`, never a
## square block and never the same as a neighbour. Turned a quarter if that fits better.
static func _choose_handmade(inner: Rect2, is_square: bool, handmade: Array, cfg: Dictionary, rng: RandomNumberGenerator, taken: Dictionary[Vector2i, String], cell: Vector2i) -> Dictionary:
	if not is_square and rng.randf() >= float(cfg.get("handmade_share", 0.0)):
		return {}
	var slack := float(cfg.get("handmade_slack", 3.0))
	var neighbours: Array[String] = []
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if taken.has(cell + d):
			neighbours.append(taken[cell + d])
	var fits: Array[Dictionary] = []
	for h: Dictionary in handmade:
		var tags: Array = h["tags"]
		if tags.has("square") != is_square or neighbours.has(str(h["name"])):
			continue
		var size: Vector2 = h["size"]
		if absf(size.x - inner.size.x) <= slack and absf(size.y - inner.size.y) <= slack:
			fits.append({"block": h, "yaw": 0.0})
		elif absf(size.y - inner.size.x) <= slack and absf(size.x - inner.size.y) <= slack:
			fits.append({"block": h, "yaw": PI / 2.0})
	if fits.is_empty():
		return {}
	var pick: Dictionary = fits[rng.randi() % fits.size()]
	var h: Dictionary = pick["block"]
	var yaw := float(pick["yaw"])
	var centre := inner.get_center()
	var markers: Array[Dictionary] = []
	for m: Dictionary in h["markers"]:
		var local: Vector3 = Basis(Vector3.UP, yaw) * (m["at"] as Vector3)
		markers.append({"kind": m["kind"], "at": Vector3(centre.x + local.x, local.y, centre.y + local.z), "yaw": deg_to_rad(float(m["yaw"])) + yaw})
	return {"name": h["name"], "rect": inner, "centre": centre, "yaw": yaw, "markers": markers, "variation": rng.randi()}

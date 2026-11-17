class_name CityLayout
extends RefCounted
## The plan of a European city, in metres on its own ground (x and z centred on the city, -z
## toward the road it joins). Streets ring it and cross it, each line nudged up to
## `street_jitter` off a regular grid so blocks differ. Each block is a perimeter block:
## a pavement round it, buildings wall to wall along all four sides with their fronts on the
## street, a courtyard in the middle, and a passage through the middle of the two long fronts
## into it. The middle block of an odd grid is left open as a square. A little taller toward
## the middle. Pure and seeded, so every machine builds the same city.

const STAIR_BAY := 3.0
const FLAT_MIN := 4.5
## The shortest building that fits: one stairwell with a flat each side.
const SHORTEST := FLAT_MIN * 2.0 + STAIR_BAY
## Per style, the apartment block's wall and roof choices to pick from (VoxApartment).
const STYLES := {
	"danish": {"walls": [0, 1], "roof": [0, 0, 1]},
}


## `cfg`: size, blocks, street_width, street_jitter, pavement, passage_width, building_depth,
## floors_edge, floors_middle, style. Returns {streets, blocks, squares, passages, yards:
## Array[Rect2], buildings: Array of {footprint: Rect2, yaw, door_out: Vector2, params}}.
static func make(cfg: Dictionary, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var size := float(cfg["size"])
	var n := int(cfg["blocks"])
	var street := float(cfg["street_width"])
	var jitter := float(cfg["street_jitter"])
	var pave := float(cfg["pavement"])
	var passage := float(cfg["passage_width"])
	var depth := float(cfg["building_depth"])
	var style: Dictionary = STYLES.get(str(cfg.get("style", "danish")), STYLES["danish"])
	var half := size / 2.0
	var pitch := (size - street * (n + 1)) / n
	# Where each street line starts, across x and across z; the outer ones stay put.
	var lines: Array[Array] = [[], []]
	for axis in 2:
		for i in n + 1:
			var at := -half + i * (pitch + street)
			if i > 0 and i < n:
				at += rng.randf_range(-jitter, jitter)
			lines[axis].append(at)
	var streets: Array[Rect2] = []
	for i in n + 1:
		streets.append(Rect2(float(lines[0][i]), -half, street, size))
		streets.append(Rect2(-half, float(lines[1][i]), size, street))
	var blocks: Array[Rect2] = []
	var squares: Array[Rect2] = []
	var passages: Array[Rect2] = []
	var yards: Array[Rect2] = []
	var buildings: Array[Dictionary] = []
	for bx in n:
		for bz in n:
			var x0 := float(lines[0][bx]) + street
			var z0 := float(lines[1][bz]) + street
			var block := Rect2(x0, z0, float(lines[0][bx + 1]) - x0, float(lines[1][bz + 1]) - z0)
			blocks.append(block)
			if n % 2 == 1 and bx == n / 2 and bz == n / 2:
				squares.append(block)
				continue
			var inner := block.grow(-pave)
			var mid := inner.get_center().x
			passages.append(Rect2(mid - passage / 2.0, inner.position.y, passage, inner.size.y))
			yards.append(inner.grow(-depth))
			# Fronts on the -z and +z streets, each in two either side of the passage, corners
			# included; then the -x and +x sides between them.
			for row in [-1, 1]:
				var zr := inner.position.y if row == -1 else inner.end.y - depth
				for foot: Rect2 in [Rect2(inner.position.x, zr, mid - passage / 2.0 - inner.position.x, depth), Rect2(mid + passage / 2.0, zr, inner.end.x - mid - passage / 2.0, depth)]:
					if foot.size.x >= SHORTEST:
						buildings.append(_building(foot, Vector2(0, row), foot.size.x, size, cfg, style, rng))
			for col in [-1, 1]:
				var xc := inner.position.x if col == -1 else inner.end.x - depth
				var foot := Rect2(xc, inner.position.y + depth, depth, inner.size.y - depth * 2.0)
				if foot.size.y >= SHORTEST:
					buildings.append(_building(foot, Vector2(col, 0), foot.size.y, size, cfg, style, rng))
	return {"streets": streets, "blocks": blocks, "squares": squares, "passages": passages, "yards": yards, "buildings": buildings}


## An apartment block filling `foot`, `length` along its street, its front toward `facing`.
static func _building(foot: Rect2, facing: Vector2, length: float, size: float, cfg: Dictionary, style: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	# As many stairwells as fit, and flats exactly as wide as fills the plot: wall to wall
	# with the neighbours, no gaps along the street.
	var stairwells := maxi(1, floori(length / SHORTEST))
	var flat := maxf((length / stairwells - STAIR_BAY) / 2.0, FLAT_MIN)
	var out := clampf(foot.get_center().length() / (size * 0.55), 0.0, 1.0)
	var floors := clampi(roundi(lerpf(float(cfg["floors_middle"]), float(cfg["floors_edge"]), out)) + rng.randi_range(-1, 0), 3, 6)
	var depth := minf(foot.size.x, foot.size.y)
	var centre := foot.get_center()
	var walls: Array = style["walls"]
	var roofs: Array = style["roof"]
	return {
		"footprint": foot,
		# The apartment's front is -Z; turned to face its street.
		"yaw": atan2(-facing.x, -facing.y) if facing != Vector2(0, -1) else 0.0,
		"door_out": centre + facing * (depth / 2.0 + 1.0),
		"params": {
			"floors": float(floors), "stairwells": float(stairwells), "flat_width": flat, "depth": depth,
			"walls": float(walls[rng.randi() % walls.size()]), "roof": float(roofs[rng.randi() % roofs.size()]),
			# No basement: its light wells would stand out on the pavement.
			"balconies": 1.0, "balcony_sides": 0.0, "interior": 1.0, "elevators": 0.0, "basement": 0.0,
			"seed": float(rng.randi_range(1, 99999)),
		},
	}

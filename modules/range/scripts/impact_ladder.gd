class_name ImpactLadder
extends RefCounted
## A fixed set of things the game can break (the range's wall samples and a house in each
## wall material) and a ladder of hits from one rifle round to a blast bigger than any weapon
## has, sent the way real ones arrive (`weapon.fired`, the `explosion` broadcast). The
## destruction table test and the `ladder` capture share it, so what the test measures is
## what the sheet shows.
##
## Every hit aims at the same spot on a subject's front (-Z) face: a quarter of the way along
## from the middle, `AIM_HEIGHT` up, clear of a house's door.

const AIM_HEIGHT := 1.3
## A blast goes off this far in front of the face, as a charge stuck on it or a rocket
## landing at its foot would.
const BLAST_STANDOFF := 0.3
const BLAST_HEIGHT := 1.0
## Rounds come from this far out, a little from above.
const SHOT_DISTANCE := 12.0
## The patch measured for how open the face is: `PATCH` metres square round the aim point,
## sampled every `PATCH_STEP`.
const PATCH := 2.0
const PATCH_STEP := 0.1
const WEAPONS := "res://modules/weapons/data/weapons.json"
const RANGE := "res://modules/range/data/range.json"
## Houses alongside the walls: one per wall material the shed comes in, one with security glass.
const HOUSES: Array[Dictionary] = [
	{"label": "House, planks", "material": "wood"},
	{"label": "House, concrete", "material": "concrete"},
	{"label": "House, brick", "material": "brick"},
	{"label": "House, brick, security glass", "material": "brick", "glass": "security_glass"},
]
const HOUSE_SIZE := Vector3(7.0, 2.9, 5.5)


## The subjects as building layout entries without a position: the range's row, then the houses.
static func subjects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cfg: Variant = Data.load_json(RANGE)
	if cfg is Dictionary:
		for e: Dictionary in ((cfg as Dictionary)["mission"]["buildings"] as Dictionary)["row"]:
			out.append(e.duplicate())
	for h in HOUSES:
		var e := h.duplicate()
		e["kind"] = "house"
		e["width"] = HOUSE_SIZE.x
		e["wall_height"] = HOUSE_SIZE.y
		e["depth"] = HOUSE_SIZE.z
		e["windows"] = 2
		out.append(e)
	return out


## The hits, smallest first within each kind: `{label, kind: "rounds", count, spread}` or
## `{label, kind: "blast", radius}`. Round damage and the charge's and rocket's blasts come
## from the weapons data, so the ladder follows them when they are tuned.
static func hits() -> Array[Dictionary]:
	var w: Dictionary = {}
	var loaded: Variant = Data.load_json(WEAPONS)
	if loaded is Dictionary:
		w = loaded
	var damage := float((w.get("rifle", {}) as Dictionary).get("damage", 25.0))
	var rocket := float((w.get("rocket", {}) as Dictionary).get("radius", 2.8))
	var charge := float((w.get("charge", {}) as Dictionary).get("radius", 3.0))
	var blasts: Array[Dictionary] = [
		{"label": "blast 1 m", "radius": 1.0},
		{"label": "blast 2 m", "radius": 2.0},
		{"label": "rocket %s m" % rocket, "radius": rocket},
		{"label": "charge %s m" % charge, "radius": charge},
		{"label": "blast 4 m", "radius": 4.0},
		{"label": "blast 6 m", "radius": 6.0},
	]
	blasts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["radius"]) < float(b["radius"]))
	var out: Array[Dictionary] = [
		{"label": "1 round", "kind": "rounds", "count": 1, "spread": 0.0, "damage": damage},
		{"label": "10 rounds, one spot", "kind": "rounds", "count": 10, "spread": 0.06, "damage": damage},
		{"label": "40 rounds, spread", "kind": "rounds", "count": 40, "spread": PATCH / 2.0, "damage": damage},
	]
	for b in blasts:
		b["kind"] = "blast"
		out.append(b)
	return out


## A layout entry for `subject` standing at `at`, facing -Z, with a fixed seed so every copy
## of a subject is built the same.
static func entry(subject: Dictionary, index: int, at: Vector3) -> Dictionary:
	var w := float(subject.get("width", 5.0))
	var d := float(subject.get("depth", 4.0))
	var e := subject.duplicate()
	e["position"] = at
	e["yaw"] = 0.0
	e["wall_height"] = float(subject.get("wall_height", 2.8))
	e["paint"] = int(subject.get("paint", 1))
	e["windows"] = int(subject.get("windows", 2))
	e["seed"] = 2000 + index
	e["radius"] = Vector2(w, d).length() / 2.0
	e["glass"] = str(subject.get("glass", "window_glass"))
	return e


## The aim point on `b`'s front face, local.
static func aim(b: MissionBuilding) -> Vector3:
	var w := float(b.spec.get("width", 5.0))
	var d := float(b.spec.get("depth", 4.0))
	return Vector3(w / 4.0, AIM_HEIGHT, -d / 2.0)


## Sends `hit` at `b` the way the game would. Rounds trace from in front like a real shot
## and stop at whatever they meet first (a round into a hole already made goes through).
static func apply(b: MissionBuilding, hit: Dictionary) -> void:
	var at := aim(b)
	if str(hit["kind"]) == "blast":
		var centre := b.global_transform * (Vector3(at.x, BLAST_HEIGHT, at.z) + Vector3(0.0, 0.0, -BLAST_STANDOFF))
		Net.server_broadcast(&"explosion", {"position": centre, "radius": float(hit["radius"]), "source": null})
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(b.spec.get("seed", 1))
	var spread := float(hit.get("spread", 0.0))
	var space := b.get_world_3d().direct_space_state
	for k in int(hit["count"]):
		var target := at + Vector3(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread), 0.0)
		target.y = maxf(target.y, MissionBuilding.SLAB + 0.1)
		var to := b.global_transform * target
		var from := b.global_transform * (target + Vector3(0.0, 0.3, -SHOT_DISTANCE))
		var query := PhysicsRayQueryParameters3D.create(from, to + (to - from).normalized() * 0.5, PhysicsLayers.BULLETS)
		var found := space.intersect_ray(query)
		if found.is_empty() or found["collider"] != b:
			continue
		EventBus.publish(&"weapon.fired", {"holder": null, "from": from, "to": found["position"], "collider": b, "damage": float(hit["damage"])})


## Share (0..1) of the patch round the aim point you can see straight through the front
## face: no voxel, glass included, anywhere along the line through it.
static func openness(b: MissionBuilding) -> float:
	var model := b.model()
	var at := aim(b)
	var thick := float(b.spec.get("depth", 4.0)) if b.is_wall() else MissionBuilding.WALL
	var front := at.z
	var steps := int(round(PATCH / PATCH_STEP))
	var open := 0
	var total := 0
	for i in steps:
		for j in steps:
			var x := at.x - PATCH / 2.0 + (float(i) + 0.5) * PATCH_STEP
			var y := at.y - PATCH / 2.0 + (float(j) + 0.5) * PATCH_STEP
			if y < MissionBuilding.SLAB:
				continue
			total += 1
			var clear := true
			var z := front + b.voxel * 0.5
			while z < front + thick:
				if model.colour_at(Vector3(x, y, z)).a > 0.0:
					clear = false
					break
				z += b.voxel * 0.5
			if clear:
				open += 1
	return float(open) / float(maxi(total, 1))

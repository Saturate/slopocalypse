class_name CampLayout
extends RefCounted
## The players' camp (#420): a square fence round the middle of the camp's levelled pad
## with a gate in the side the highway leaves by, and the spots inside it where the hut,
## the respawn, the mission board, the trader's stall, the transport and the players' car
## stand. Laid out from world.json `camp` and the map, so every machine gets the same camp
## with nothing sent. Camp-local metres run [x, z]: x to the right as you face the gate, z
## toward the gate, from the pad's middle.

const CONFIG := "res://modules/world/data/world.json"
const SPOTS: Array[String] = ["respawn", "hut", "board", "trader", "transport", "car"]

## The middle of the pad, on its level.
var centre := Vector3.ZERO
## Unit, on the ground plane: from the middle toward the gate.
var out := Vector3.FORWARD
## Unit, on the ground plane: to the right as you face the gate.
var right := Vector3.RIGHT
## The levelled ground (x, z) the camp stands on.
var pad := Rect2()
## Metres from the middle to each side of the fence.
var half := 0.0
## Metres across the gate.
var gate_width := 0.0
## The hut's floor size, [across, deep] metres.
var hut_size := Vector2.ZERO

var _spots: Dictionary[String, Transform3D] = {}


## What is wrong with a `camp` config, or "" when nothing is.
static func check(cfg: Dictionary) -> String:
	for key: String in ["fence", "gate"]:
		if not (cfg.get(key) is float or cfg.get(key) is int) or float(cfg[key]) <= 0.0:
			return "%s: metres, more than 0" % key
	if float(cfg["gate"]) >= float(cfg["fence"]) * 2.0:
		return "gate: narrower than the fence"
	if not cfg.get("spots") is Dictionary:
		return "spots: missing"
	for name in SPOTS:
		var spot: Variant = (cfg["spots"] as Dictionary).get(name)
		if not spot is Dictionary or not _pair((spot as Dictionary).get("at")) or not _pair((spot as Dictionary).get("toward")):
			return "spots.%s: {at: [x, z], toward: [x, z]}" % name
	if not _pair((cfg["spots"]["hut"] as Dictionary).get("size")):
		return "spots.hut.size: [across, deep]"
	return ""


static func _pair(v: Variant) -> bool:
	return v is Array and (v as Array).size() == 2 and (v as Array).all(func(n: Variant) -> bool: return n is float or n is int)


## The camp on a pad (`footprint` on x, z) whose middle is `middle` on its level, its gate in
## the side `toward` points at.
static func make(middle: Vector3, toward: Vector3, footprint: Rect2, cfg: Dictionary) -> CampLayout:
	var camp := CampLayout.new()
	camp.centre = middle
	var flat := Vector3(toward.x, 0.0, toward.z)
	camp.out = flat.normalized() if flat.length() > 0.001 else Vector3.FORWARD
	camp.right = camp.out.cross(Vector3.UP).normalized()
	camp.pad = footprint
	camp.half = float(cfg["fence"])
	camp.gate_width = float(cfg["gate"])
	var spots: Dictionary = cfg["spots"]
	camp.hut_size = _vec2(spots["hut"]["size"])
	for name in SPOTS:
		var spot: Dictionary = spots[name]
		var at := camp.point(_vec2(spot["at"]))
		var face := _vec2(spot["toward"])
		var look := camp.right * face.x + camp.out * face.y
		camp._spots[name] = Transform3D(Basis.looking_at(look if look.length() > 0.001 else camp.out, Vector3.UP), at)
	return camp


## For a world without a map's camp (the flat test world, tests): the camp laid out so its
## respawn spot is `respawn` (on the ground), the gate toward `toward`, on a pad just round
## the fence.
static func around(respawn: Vector3, toward: Vector3, cfg: Dictionary) -> CampLayout:
	var probe := make(Vector3.ZERO, toward, Rect2(), cfg)
	var middle := respawn - probe.spot("respawn").origin
	var side := (float(cfg["fence"]) + 2.0) * 2.0
	return make(middle, toward, Rect2(Vector2(middle.x, middle.z) - Vector2.ONE * side / 2.0, Vector2.ONE * side), cfg)


## The camp a `world.ready` payload carries, or one laid out round its spawn (the spawn
## marker floats a metre over the ground) facing its `forward`; null without a usable config.
static func of_ready(payload: Dictionary) -> CampLayout:
	var given: Variant = payload.get("camp")
	if given is CampLayout:
		return given
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not (data as Dictionary).get("camp") is Dictionary or not check(data["camp"]).is_empty():
		return null
	var spawn: Vector3 = payload.get("spawn", Vector3.ZERO)
	return around(spawn - Vector3.UP, payload.get("forward", Vector3.FORWARD), data["camp"])


static func _vec2(v: Array) -> Vector2:
	return Vector2(float(v[0]), float(v[1]))


## Camp-local [x, z] on the pad's level.
func point(local: Vector2) -> Vector3:
	return centre + right * local.x + out * local.y


## (x, z) of `p` in camp-local metres.
func local_of(p: Vector3) -> Vector2:
	var d := Vector3(p.x - centre.x, 0.0, p.z - centre.z)
	return Vector2(d.dot(right), d.dot(out))


## Where `name` (one of SPOTS) stands, on the pad's level; its -Z looks the way the spot's
## `toward` says.
func spot(name: String) -> Transform3D:
	return _spots.get(name, Transform3D(Basis.IDENTITY, centre))


## The middle of the gate, on the pad's level.
func gate() -> Vector3:
	return point(Vector2(0.0, half))


## Whether `p` is inside the fence, at least `margin` metres in from it (a negative margin
## reaches past it).
func inside(p: Vector3, margin := 0.0) -> bool:
	var l := local_of(p)
	return absf(l.x) <= half - margin and absf(l.y) <= half - margin


## Metres from `p` (on the ground plane) to the fence's square, 0 inside it.
func distance(p: Vector3) -> float:
	var l := local_of(p)
	return Vector2(maxf(absf(l.x) - half, 0.0), maxf(absf(l.y) - half, 0.0)).length()


## Whether `p` lies in the gate's opening, `reach` metres either side of the fence line.
func in_gate(p: Vector3, reach: float) -> bool:
	var l := local_of(p)
	return absf(l.x) <= gate_width / 2.0 and absf(l.y - half) <= reach


## `way` (a step on the ground plane) from `at` with the part that would carry a walker
## into the camp taken out. Outside, where `ahead` metres on would be inside the fence, the
## part across each side it would cross goes (so it slides along the fence, round a corner);
## inside, the part toward the middle across its nearest side goes, so it can walk out or
## along but never deeper.
func keep_out_step(at: Vector3, way: Vector3, ahead: float) -> Vector3:
	var w := Vector2(way.dot(right), way.dot(out))
	if w.length() < 0.001:
		return way
	var l := local_of(at)
	if inside(at):
		var axis := 0 if absf(l.x) >= absf(l.y) else 1
		var side := 1.0 if l[axis] >= 0.0 else -1.0
		if w[axis] * side < 0.0:
			w[axis] = 0.0
	else:
		for axis in 2:
			if _enters(at, w, ahead) and absf(l[axis]) >= half and w[axis] * signf(l[axis]) < 0.0:
				w[axis] = 0.0
		if _enters(at, w, ahead):
			w = Vector2.ZERO
	return right * w.x + out * w.y


## Whether a step along camp-local `w` from `at` puts `ahead` metres on inside the fence.
func _enters(at: Vector3, w: Vector2, ahead: float) -> bool:
	if w.length() < 0.001:
		return false
	return inside(at + (right * w.x + out * w.y).normalized() * ahead)


## The fence as straight runs, each [from, to] on the pad's level: the back and both sides
## whole, the gate side in two either side of the gate.
func fence_runs() -> Array[PackedVector3Array]:
	var h := half
	var g := gate_width / 2.0
	var runs: Array[PackedVector3Array] = []
	for pair: Array in [[Vector2(-h, -h), Vector2(h, -h)], [Vector2(-h, -h), Vector2(-h, h)], [Vector2(h, -h), Vector2(h, h)],
			[Vector2(-h, h), Vector2(-g, h)], [Vector2(g, h), Vector2(h, h)]]:
		runs.append(PackedVector3Array([point(pair[0]), point(pair[1])]))
	return runs

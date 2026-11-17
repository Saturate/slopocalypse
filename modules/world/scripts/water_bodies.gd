class_name WaterBodies
extends RefCounted
## Ponds and lakes: each a flat surface at one `level` inside an outline (x, z points). Not a
## fluid: "how deep is it here" is worked out from this data and the ground, the same on the
## server and every client, so nothing about water is ever sent.
##
## A body's level is where the ground along its outline is lowest, less `freeboard`, so the
## water meets the bank instead of floating above a dip in it. Inside, the ground is cut down
## to a bed that slopes from the edge to `depth` below the level over `shore` metres; outside,
## higher ground eases down to just over the level within `bank` metres, so a pond on a slope
## gets a sloping bank instead of a pit.
## Runs without autoloads (the world builder uses TerrainHeights).

## Each: {outline: PackedVector2Array, level, depth, box: Rect2}.
var bodies: Array[Dictionary] = []
## Craters that dipped below a body's level next to it, flooded to that level: each
## Vector4(x, z, radius at the surface, level).
var puddles: Array[Vector4] = []
var shore := 4.0
var bank := 8.0
## How far above the water the bank starts at the edge.
const BANK_LIP := 0.25


## `config`: the `water` block of world.json. `ground(x, z)` is the land before any water.
func _init(config: Dictionary, ground: Callable) -> void:
	shore = float(config.get("shore", 4.0))
	bank = float(config.get("bank", 8.0))
	var freeboard := float(config.get("freeboard", 0.15))
	for entry: Variant in config.get("bodies", []):
		var b: Dictionary = entry
		var outline := PackedVector2Array()
		for p: Array in b["outline"]:
			outline.append(Vector2(float(p[0]), float(p[1])))
		if outline.size() < 3:
			continue
		var box := Rect2(outline[0], Vector2.ZERO)
		var lowest := INF
		for i in outline.size():
			box = box.expand(outline[i])
			# The edge's ends and middles, so a dip between corners counts too.
			var mid := (outline[i] + outline[(i + 1) % outline.size()]) / 2.0
			lowest = minf(lowest, minf(float(ground.call(outline[i].x, outline[i].y)), float(ground.call(mid.x, mid.y))))
		bodies.append({"name": str(b.get("name", "")), "outline": outline, "level": lowest - freeboard, "depth": float(b.get("depth", 2.0)), "box": box})


## The body whose outline holds x, z, or -1.
func body_at(x: float, z: float) -> int:
	var p := Vector2(x, z)
	for i in bodies.size():
		var b := bodies[i]
		if (b["box"] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, b["outline"]):
			return i
	return -1


## The ground at x, z with any water's bed and bank cut into `dry` (the ground without water).
func carve(x: float, z: float, dry: float) -> float:
	var p := Vector2(x, z)
	for b in bodies:
		if not (b["box"] as Rect2).grow(bank).has_point(p):
			continue
		var level := float(b["level"])
		var from_edge := edge_distance(p, b["outline"])
		if Geometry2D.is_point_in_polygon(p, b["outline"]):
			return minf(dry, level - float(b["depth"]) * smoothstep(0.0, shore, from_edge))
		if from_edge < bank:
			return minf(dry, lerpf(level + BANK_LIP, dry, smoothstep(0.0, bank, from_edge)))
	return dry


## How deep the water is over `ground` at x, z: 0 outside every body.
func depth(x: float, z: float, ground: float) -> float:
	var i := body_at(x, z)
	return maxf(float(bodies[i]["level"]) - ground, 0.0) if i >= 0 else 0.0


func level_of(i: int) -> float:
	return float(bodies[i]["level"])


## The water level at x, z: a body's, a flooded crater's, or NAN where there is none.
func level_at(x: float, z: float) -> float:
	var i := body_at(x, z)
	if i >= 0:
		return level_of(i)
	for p in puddles:
		if Vector2(x - p.x, z - p.y).length_squared() < p.z * p.z:
			return p.w
	return NAN


## A crater, a sphere at `centre` of `radius` dug into the ground, floods if it reaches
## below the level of a body it is in or beside (within the body's bank): the water fills it
## up to that level. Returns the puddle as Vector4(x, z, radius at the surface, level), or
## Vector4.ZERO when it stays dry (or lies inside the body, whose surface already covers it).
func flood(centre: Vector3, radius: float) -> Vector4:
	var p := Vector2(centre.x, centre.z)
	for b in bodies:
		if not (b["box"] as Rect2).grow(bank + radius).has_point(p):
			continue
		var level := float(b["level"])
		if centre.y - radius >= level:
			continue
		if Geometry2D.is_point_in_polygon(p, b["outline"]):
			return Vector4.ZERO
		if edge_distance(p, b["outline"]) > bank + radius:
			continue
		# Where the crater's bowl meets the water's surface.
		var up := level - centre.y
		var at_surface := sqrt(maxf(radius * radius - up * up, 0.0))
		if at_surface <= 0.05:
			continue
		var puddle := Vector4(centre.x, centre.z, at_surface, level)
		puddles.append(puddle)
		return puddle
	return Vector4.ZERO


## Distance from `p` to the nearest edge of `outline`.
static func edge_distance(p: Vector2, outline: PackedVector2Array) -> float:
	var best := INF
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best

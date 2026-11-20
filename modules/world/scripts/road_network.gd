class_name RoadNetwork
extends RefCounted
## The roads between a map's settlements (#428, decision 0010): a highway from the players'
## camp to the city, a two-lane road from the city to each town. Each is routed over the
## land by a cheapest-path search on the zone grid (steep steps, woods, wet and sloping
## ground cost more; water and other settlements are avoided), pulled straight where it
## safely can be, its corners rounded into arcs, and sampled evenly. Later slices give the roads a profile and cut them into the land.
## Pure and seeded through its settlements; no autoloads.

## Easing passes after the arcs (see `_ease`).
const EASE_PASSES := 6
## Metres between points drawn along a corner's arc.
const ARC_STEP := 2.0
## Metres between checks along a straight run.
const CHECK_STEP := 4.0
## A straight run may climb this much steeper than the road's limit; the profile evens it.
const STRAIGHT_SLACK := 1.5
const STRAIGHT := 1.0
const DIAGONAL := 1.4142135
const STEPS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var settlements: Settlements

var _cfg: Dictionary
## Each {kind, from, to, points (x, z every `sample` metres), width, max_grade}.
var _roads: Array[Dictionary] = []


func _init(places: Settlements, config: Dictionary) -> void:
	settlements = places
	_cfg = config
	var city := places.city()
	if city.is_empty():
		return
	_join(&"highway", "camp", places.camp(), {}, "city", city)
	for i in places.towns().size():
		var town: Dictionary = places.towns()[i]
		# From the town's side nearest the city to the city.
		_join(&"two_lane", "town %d" % i, _nearest_connector(town, city["centre"]), town, "city", city)


func roads() -> Array[Dictionary]:
	return _roads


func _nearest_connector(place: Dictionary, to: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	for c: Vector3 in place["connectors"]:
		var p := Vector2(c.x, c.z)
		if p.distance_to(to) < best_d:
			best_d = p.distance_to(to)
			best = p
	return best


## A road of `kind` from `start` (a side of `from_place`, or open ground when that is empty)
## to the side of `place` nearest it. At a settlement's side the road leaves or arrives
## square to it, straight for its last metres, so smoothing never cuts a corner into it.
func _join(kind: StringName, from_name: String, start: Vector2, from_place: Dictionary, to_name: String, place: Dictionary) -> void:
	var end := _nearest_connector(place, start)
	var cell := settlements.zones.cell_size()
	var kind_cfg: Dictionary = (_cfg["kinds"] as Dictionary)[String(kind)]
	var out_from := _outward(from_place, start) if not from_place.is_empty() else Vector2.ZERO
	var out_to := _outward(place, end)
	var max_grade := float(kind_cfg["max_grade"])
	var path := _route(start + out_from * cell * 3.0, end + out_to * cell * 3.0, max_grade)
	if path.is_empty():
		return
	path = _straighten(path, max_grade)
	path.append(end + out_to * cell)
	if out_from != Vector2.ZERO:
		path.insert(0, start + out_from * cell)
	var curve := _round_corners(path, float(kind_cfg["min_radius"]))
	curve.append(end)
	if out_from != Vector2.ZERO:
		curve.insert(0, start)
	var points := _resample(_ease(_resample(curve, float(_cfg["sample"])), EASE_PASSES), float(_cfg["sample"]))
	_roads.append({"kind": String(kind), "from": from_name, "to": to_name, "points": points,
		"width": float(kind_cfg["width"]), "max_grade": float(kind_cfg["max_grade"])})


## Out of `place` square to its side at `at`.
static func _outward(place: Dictionary, at: Vector2) -> Vector2:
	var off := at - (place["footprint"] as Rect2).get_center()
	return Vector2(signf(off.x), 0.0) if absf(off.x) > absf(off.y) else Vector2(0.0, signf(off.y))


## The cheapest way over the zone grid from `a` to `b` (A*), as cell centres, starting at `a`.
func _route(a: Vector2, b: Vector2, max_grade: float) -> PackedVector2Array:
	var zones := settlements.zones
	var land := zones.land
	var n := zones.side()
	var cell := zones.cell_size()
	var origin := land.bounds().position
	var to_cell := func(p: Vector2) -> Vector2i:
		return Vector2i(clampi(floori((p.x - origin.x) / cell), 0, n - 1), clampi(floori((p.y - origin.y) / cell), 0, n - 1))
	var start: Vector2i = to_cell.call(a)
	var goal: Vector2i = to_cell.call(b)
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var extra := PackedFloat32Array()
	extra.resize(n * n)
	var cost: Dictionary = _cfg["cost"]
	var places: Array[Dictionary] = [settlements.city()]
	places.append_array(settlements.towns())
	for j in n:
		for i in n:
			var c := zones.cell_centre(i, j)
			var k := j * n + i
			heights[k] = land.height(c.x, c.y)
			var kind := str(zones.zone_at(c.x, c.y)["kind"])
			if kind == "water":
				extra[k] = -1.0
				continue
			extra[k] = float(cost.get(kind, 0.0))
			for place in places:
				if (place["footprint"] as Rect2).grow(-cell * 0.5).has_point(c):
					extra[k] = -1.0
	var best := PackedFloat32Array()
	best.resize(n * n)
	best.fill(INF)
	var came := PackedInt32Array()
	came.resize(n * n)
	came.fill(-1)
	var heap := MinHeap.new()
	var s := start.y * n + start.x
	var g := goal.y * n + goal.x
	best[s] = 0.0
	heap.push(0.0, s)
	var over := float(cost["over_grade"])
	while not heap.is_empty():
		var k := heap.pop()
		if k == g:
			break
		var i := k % n
		var j := k / n
		for step: Vector2i in STEPS:
			var ni := i + step.x
			var nj := j + step.y
			if ni < 0 or nj < 0 or ni >= n or nj >= n:
				continue
			var nk := nj * n + ni
			if extra[nk] < 0.0 and nk != g:
				continue
			var run := (DIAGONAL if step.x != 0 and step.y != 0 else STRAIGHT) * cell
			var grade := absf(heights[nk] - heights[k]) / run
			var step_cost := run * (1.0 + maxf(extra[nk], 0.0))
			if grade > max_grade:
				step_cost += run * over * (grade - max_grade) / max_grade
			var total := best[k] + step_cost
			if total < best[nk]:
				best[nk] = total
				came[nk] = k
				var left := Vector2(goal - Vector2i(ni, nj)).length() * cell
				heap.push(total + left, nk)
	if came[g] < 0 and g != s:
		return PackedVector2Array()
	var cells: Array[int] = []
	var at := g
	while at != s and at >= 0:
		cells.append(at)
		at = came[at]
	cells.reverse()
	var out := PackedVector2Array([a])
	for k in cells:
		out.append(zones.cell_centre(k % n, k / n))
	return out


## The grid path pulled straight: from each point, on to the furthest later point the road
## can run to in a straight line without crossing water or a settlement or climbing steeper
## than `max_grade` (with some slack the profile will smooth out). Removes the staircase of a
## path over grid cells, so smoothing makes long easy curves.
func _straighten(path: PackedVector2Array, max_grade: float) -> PackedVector2Array:
	var out := PackedVector2Array([path[0]])
	var i := 0
	while i < path.size() - 1:
		var j := path.size() - 1
		while j > i + 1 and not _clear_run(path[i], path[j], max_grade * STRAIGHT_SLACK):
			j -= 1
		out.append(path[j])
		i = j
	return out


## Whether a straight road from `a` to `b` stays out of water (and the wet band round it)
## and settlements and nowhere
## climbs steeper than `max_grade` between samples.
func _clear_run(a: Vector2, b: Vector2, max_grade: float) -> bool:
	var land := settlements.zones.land
	var places: Array[Dictionary] = [settlements.city()]
	places.append_array(settlements.towns())
	var steps := maxi(ceili(a.distance_to(b) / CHECK_STEP), 1)
	var last := land.height(a.x, a.y)
	for k in range(1, steps + 1):
		var p := a.lerp(b, float(k) / steps)
		# The wet band round water too: smoothing later rounds corners, and must not round
		# one into a pond.
		var kind := str(settlements.zones.zone_at(p.x, p.y).get("kind", ""))
		if kind == "water" or kind == "wetland" or not is_nan(land.water_level(p.x, p.y)):
			return false
		for place in places:
			if (place["footprint"] as Rect2).grow(-1.0).has_point(p):
				return false
		var h := land.height(p.x, p.y)
		if absf(h - last) / (a.distance_to(b) / steps) > max_grade:
			return false
		last = h
	return true


## Each corner rounded into a circular arc of `radius` (smaller where the straights either
## side are too short for it), drawn every `ARC_STEP` metres; the ends kept. Arcs spread a
## turn evenly, so no stretch of road turns sharply.
static func _round_corners(points: PackedVector2Array, radius: float) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var out := PackedVector2Array([points[0]])
	for i in range(1, points.size() - 1):
		var a := points[i - 1]
		var b := points[i]
		var c := points[i + 1]
		var into := (b - a).normalized()
		var out_dir := (c - b).normalized()
		var turn := into.angle_to(out_dir)
		if absf(turn) < 0.001:
			out.append(b)
			continue
		# How far back from the corner the arc starts, no more than half of either straight.
		var reach := minf(radius * tan(absf(turn) / 2.0), minf(a.distance_to(b), b.distance_to(c)) / 2.0)
		var r := reach / tan(absf(turn) / 2.0)
		var from := b - into * reach
		var centre := from + into.orthogonal() * r * (-signf(turn))
		var start_angle := (from - centre).angle()
		var steps := maxi(ceili(absf(turn) * r / ARC_STEP), 1)
		for k in steps + 1:
			out.append(centre + Vector2.from_angle(start_angle + turn * float(k) / steps) * r)
	out.append(points[points.size() - 1])
	return out


## Each inner point moved halfway towards the middle of its neighbours, `passes` times, the
## ends held: spreads out a wiggle where two corners came too close for their arcs.
static func _ease(points: PackedVector2Array, passes: int) -> PackedVector2Array:
	var p := points
	for pass_index in passes:
		var out := p.duplicate()
		for i in range(1, p.size() - 1):
			out[i] = p[i].lerp((p[i - 1] + p[i + 1]) / 2.0, 0.5)
		p = out
	return p


## The line through `points` sampled every `step` metres, its last point kept.
static func _resample(points: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([points[0]])
	var carry := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		var d := step - carry
		while d <= length:
			out.append(a.lerp(b, d / length))
			d += step
		carry = length - (d - step)
	var last := points[points.size() - 1]
	if out[out.size() - 1].distance_to(last) > step * 0.5:
		out.append(last)
	else:
		out[out.size() - 1] = last
	return out

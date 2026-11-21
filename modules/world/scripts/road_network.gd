class_name RoadNetwork
extends RefCounted
## The roads between a map's settlements (#428, decision 0010): a highway from the players'
## camp to the city, a two-lane road from the city to each town. Each is routed over the
## land by a cheapest-path search on the zone grid (steep steps, woods, wet and sloping
## ground cost more; water and other settlements are avoided), pulled straight where it
## safely can be, its corners rounded into arcs, and sampled evenly. Later slices give the roads a profile and cut them into the land.
## Pure and seeded through its settlements; no autoloads.

## Most forward and backward passes holding a profile to its grade (see `_profile`).
const PROFILE_PASSES := 64
## Easing passes after the arcs (see `_ease`).
const EASE_PASSES := 6
## Most a track turns from one sample to the next (radians), and the most extra easing passes
## spent getting it there.
const MAX_TRACK_TURN := 0.8
const UNKINK_PASSES := 48
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
## The routing grid, built once: each cell's height, its extra cost (-1: impassable), and
## the land's slope there (rise per metre along x and z).
var _heights := PackedFloat32Array()
var _extra := PackedFloat32Array()
var _slopes := PackedVector2Array()
## Footprints a route may not cross besides water and settlements (other sites, for a track).
var _avoid: Array[Rect2] = []


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


## Half a track's width: room kept between a track and a site it passes.
func _track_half() -> float:
	var kinds: Dictionary = _cfg["kinds"]
	return float((kinds["track"] as Dictionary)["width"]) / 2.0 if kinds.has("track") else 0.0


## A track from `site` ({footprint, level, connectors}) to the nearest point on a main road
## (#429), of the recipe's `track` kind, routed like the roads but around `avoid` (other
## sites). Nothing when the recipe has no track kind or no way is found.
func add_track(site: Dictionary, name: String, avoid: Array[Rect2]) -> void:
	if not (_cfg["kinds"] as Dictionary).has("track"):
		return
	var centre: Vector2 = (site["footprint"] as Rect2).get_center()
	# The nearest point on each road, and on each track built before (sites share tracks
	# rather than running side by side); the one with the shortest way there wins, so a road
	# just across a lake does not pull a track all the way round it.
	var targets: Array[Vector3] = []
	for road in _roads:
		var points: PackedVector2Array = road["points"]
		var heights: PackedFloat32Array = road["heights"]
		var nearest := -1
		var nearest_d := INF
		for k in points.size():
			var d := points[k].distance_to(centre)
			# Not where a track leaves another site: joining there would end against it.
			if d < nearest_d and avoid.all(func(r: Rect2) -> bool: return not r.grow(_track_half() + 2.0).has_point(points[k])):
				nearest_d = d
				nearest = k
		if nearest >= 0:
			targets.append(Vector3(points[nearest].x, heights[nearest], points[nearest].y))
	if targets.is_empty():
		return
	_avoid = avoid
	var kind_cfg: Dictionary = (_cfg["kinds"] as Dictionary)["track"]
	# Each target's way there, shortest first.
	var ways: Array[Vector4] = []
	for t in targets:
		var way := _route(centre, Vector2(t.x, t.z), float(kind_cfg["max_grade"]), float(kind_cfg.get("cross_slope", 0.0)))
		if way.is_empty():
			continue
		var length := 0.0
		for k in range(1, way.size()):
			length += way[k].distance_to(way[k - 1])
		ways.append(Vector4(t.x, t.y, t.z, length))
	ways.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.w < b.w)
	var cell := settlements.zones.cell_size()
	var sides: Array[Vector2] = []
	for c: Vector3 in site["connectors"]:
		sides.append(Vector2(c.x, c.z))
	for w in ways:
		var to := Vector2(w.x, w.z)
		# The road end of a track: a point on the road, met square from the side it comes from.
		var on_road := {"footprint": Rect2(to - Vector2.ONE, Vector2.ONE * 2.0), "level": w.y, "connectors": [Vector3(to.x, w.y, to.y)]}
		# Out of the side nearest the road whose straight lead-in (three cells, see `_join`)
		# is clear of the sites beside it: a water tower stands right by its farm.
		sides.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.distance_to(to) < q.distance_to(to))
		var start := Vector2.INF
		for side in sides:
			var lead := side + _outward(site, side) * cell * 3.0
			if avoid.all(func(r: Rect2) -> bool: return not MapSites.segment_hits(r.grow(_track_half()), side, lead)):
				start = side
				break
		if start == Vector2.INF:
			continue
		# Pinned at the road only; the site's pad is then levelled to where the track
		# arrives, so a site well above or below the road still gets a track within its grade.
		var free := site.duplicate()
		free["level"] = NAN
		_join(&"track", name, start, free, "road", on_road)
		if _roads.is_empty() or _roads.back()["from"] != name:
			continue
		# Rounding corners and the square approach can still shift a track onto a site
		# beside it: then the next way is tried.
		var track: Dictionary = _roads.back()
		var crosses := false
		for p: Vector2 in track["points"]:
			if avoid.any(func(r: Rect2) -> bool: return r.grow(_track_half()).has_point(p)):
				crosses = true
				break
		if crosses:
			_roads.pop_back()
			continue
		var level := float((track["heights"] as PackedFloat32Array)[0])
		site["level"] = level
		var moved: Array[Vector3] = []
		for c: Vector3 in site["connectors"]:
			moved.append(Vector3(c.x, level, c.z))
		site["connectors"] = moved
		break
	_avoid = []


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
	var path := _route(start + out_from * cell * 3.0, end + out_to * cell * 3.0, max_grade, float(kind_cfg.get("cross_slope", 0.0)))
	if path.is_empty():
		return
	# A track winds over the land; pulling a long one straight also costs seconds, testing a
	# line from each point to every later one.
	if kind != &"track":
		path = _straighten(path, max_grade)
	path.append(end + out_to * cell)
	if out_from != Vector2.ZERO:
		path.insert(0, start + out_from * cell)
	var curve := _round_corners(path, float(kind_cfg["min_radius"]))
	curve.append(end)
	if out_from != Vector2.ZERO:
		curve.insert(0, start)
	var points := _resample(_ease(_resample(curve, float(_cfg["sample"])), EASE_PASSES), float(_cfg["sample"]))
	# Legs of a winding track that run side by side would be drawn over each other and
	# fight over the ground between them: the loop between them is cut out.
	# Eased again after, so neither the join nor a short lead-in turning back towards the road
	# leaves a kink the drawn track would fold over at.
	if kind == &"track":
		points = _unkink(_resample(_ease(merge_legs(points, float(kind_cfg["width"])), EASE_PASSES), float(_cfg["sample"])), float(_cfg["sample"]))
	var land := settlements.zones.land
	var start_level := float(from_place["level"]) if not from_place.is_empty() else land.height(start.x, start.y)
	# A kind may follow the land more closely than the main roads (a dirt track, 8 m).
	var window := float(kind_cfg.get("profile_window", _cfg["profile_window"]))
	var heights := _profile(points, start_level, float(place["level"]), max_grade, window)
	var road := {"kind": String(kind), "from": from_name, "to": to_name, "points": points, "heights": heights,
		"width": float(kind_cfg["width"]), "max_grade": max_grade,
		"max_cut": float(kind_cfg["max_cut"]), "max_fill": float(kind_cfg["max_fill"])}
	# A track is always cut and filled: nobody builds a bridge or tunnel for a dirt track.
	var spans := kind != &"track"
	road["tunnels"] = _spans(points, heights, func(ground: float, h: float) -> bool: return ground - h > float(kind_cfg["max_cut"])) if spans else ([] as Array[Vector2i])
	road["bridges"] = _spans(points, heights, func(ground: float, h: float) -> bool: return h - ground > float(kind_cfg["max_fill"])) if spans else ([] as Array[Vector2i])
	_roads.append(road)


## The road's height at each of `points`: the land under it averaged over `profile_window`
## metres, pinned to `from` and `to` at its ends, then held to `max_grade` between samples by
## passes forwards and backwards until nothing moves (it always settles when the ends are
## reachable at that grade).
func _profile(points: PackedVector2Array, from: float, to: float, max_grade: float, window: float) -> PackedFloat32Array:
	var land := settlements.zones.land
	var n := points.size()
	var ground := PackedFloat32Array()
	ground.resize(n)
	for i in n:
		ground[i] = land.height(points[i].x, points[i].y)
	var half := maxi(int(window / float(_cfg["sample"]) / 2.0), 0)
	var h := PackedFloat32Array()
	h.resize(n)
	for i in n:
		var total := 0.0
		var count := 0
		for k in range(maxi(i - half, 0), mini(i + half, n - 1) + 1):
			total += ground[k]
			count += 1
		h[i] = total / count
	# A NAN start is free (a track's site end): it follows the land, held to the grade from
	# the pinned end, so the profile always settles.
	var free_start := is_nan(from)
	if not free_start:
		h[0] = from
	h[n - 1] = to
	var first := 0 if free_start else 1
	for pass_index in PROFILE_PASSES:
		var moved := false
		for i in range(1, n - 1):
			var step := max_grade * points[i].distance_to(points[i - 1])
			var held := clampf(h[i], h[i - 1] - step, h[i - 1] + step)
			moved = moved or held != h[i]
			h[i] = held
		for i in range(n - 2, first - 1, -1):
			var step := max_grade * points[i].distance_to(points[i + 1])
			var held := clampf(h[i], h[i + 1] - step, h[i + 1] + step)
			moved = moved or held != h[i]
			h[i] = held
		if not moved:
			break
	return h


## Runs of samples where `test(ground, road height)` holds, as [first, last] indices.
func _spans(points: PackedVector2Array, heights: PackedFloat32Array, test: Callable) -> Array[Vector2i]:
	var land := settlements.zones.land
	var out: Array[Vector2i] = []
	var open := -1
	for i in points.size():
		var hit: bool = test.call(land.height(points[i].x, points[i].y), heights[i])
		if hit and open < 0:
			open = i
		elif not hit and open >= 0:
			out.append(Vector2i(open, i - 1))
			open = -1
	if open >= 0:
		out.append(Vector2i(open, points.size() - 1))
	return out


## Out of `place` square to its side at `at`.
static func _outward(place: Dictionary, at: Vector2) -> Vector2:
	var off := at - (place["footprint"] as Rect2).get_center()
	return Vector2(signf(off.x), 0.0) if absf(off.x) > absf(off.y) else Vector2(0.0, signf(off.y))


## The cheapest way over the zone grid from `a` to `b` (A*), as cell centres, starting at `a`.
## `cross` is the extra cost per metre per unit of the land's slope across the way: a way
## along a hillside needs a notch cut into it, and winds into switchbacks.
func _route(a: Vector2, b: Vector2, max_grade: float, cross := 0.0) -> PackedVector2Array:
	var zones := settlements.zones
	var land := zones.land
	var n := zones.side()
	var cell := zones.cell_size()
	var origin := land.bounds().position
	var to_cell := func(p: Vector2) -> Vector2i:
		return Vector2i(clampi(floori((p.x - origin.x) / cell), 0, n - 1), clampi(floori((p.y - origin.y) / cell), 0, n - 1))
	var start: Vector2i = to_cell.call(a)
	var goal: Vector2i = to_cell.call(b)
	var cost: Dictionary = _cfg["cost"]
	# The grid's heights and costs are the same for every route: worked out once.
	if _heights.is_empty():
		_heights.resize(n * n)
		_extra.resize(n * n)
		var places: Array[Dictionary] = [settlements.city()]
		places.append_array(settlements.towns())
		for j in n:
			for i in n:
				var c := zones.cell_centre(i, j)
				var k := j * n + i
				_heights[k] = land.height(c.x, c.y)
				var kind := str(zones.zone_at(c.x, c.y)["kind"])
				if kind == "water":
					_extra[k] = -1.0
					continue
				_extra[k] = float(cost.get(kind, 0.0))
				for place in places:
					if (place["footprint"] as Rect2).grow(-cell * 0.5).has_point(c):
						_extra[k] = -1.0
	if _slopes.is_empty():
		_slopes = _grid_slopes(_heights, n, cell)
	var heights := _heights
	var extra := _extra
	if not _avoid.is_empty():
		extra = _extra.duplicate()
		# Every cell a footprint (with room for the track beside it) touches, however small.
		for rect in _avoid:
			var grown := rect.grow(_track_half())
			var from := Vector2i(clampi(floori((grown.position.x - origin.x) / cell), 0, n - 1), clampi(floori((grown.position.y - origin.y) / cell), 0, n - 1))
			var to := Vector2i(clampi(floori((grown.end.x - origin.x) / cell), 0, n - 1), clampi(floori((grown.end.y - origin.y) / cell), 0, n - 1))
			for j in range(from.y, to.y + 1):
				for i in range(from.x, to.x + 1):
					extra[j * n + i] = -1.0
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
	# Each cell expanded once: an older, dearer entry for it may still be in the heap, and
	# expanding it again multiplies the work on rough ground (seconds for one long track).
	var done := PackedByteArray()
	done.resize(n * n)
	while not heap.is_empty():
		var k := heap.pop()
		if k == g:
			break
		if done[k] == 1:
			continue
		done[k] = 1
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
			if cross > 0.0:
				var across := Vector2(-step.y, step.x).normalized()
				step_cost += run * cross * absf(_slopes[nk].dot(across))
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
		for rect in _avoid:
			if rect.grow(_track_half()).has_point(p):
				return false
		var h := land.height(p.x, p.y)
		if absf(h - last) / (a.distance_to(b) / steps) > max_grade:
			return false
		last = h
	return true


## `points` eased a pass at a time until no sample turns more than MAX_TRACK_TURN from the
## one before (or the passes run out), resampled every `step` metres.
static func _unkink(points: PackedVector2Array, step: float) -> PackedVector2Array:
	var p := points
	for pass_index in UNKINK_PASSES:
		if sharpest_turn(p) <= MAX_TRACK_TURN:
			break
		p = _resample(_ease(p, 1), step)
	return p


## The most `points` turns from one segment to the next (radians).
static func sharpest_turn(points: PackedVector2Array) -> float:
	var out := 0.0
	for k in range(1, points.size() - 1):
		out = maxf(out, absf((points[k] - points[k - 1]).angle_to(points[k + 1] - points[k])))
	return out


## The land's slope (rise per metre along x and z) at each cell of an `n` x `n` grid of
## `heights` `cell` metres apart, from its neighbours either side (one side at the edges).
static func _grid_slopes(heights: PackedFloat32Array, n: int, cell: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(n * n)
	for j in n:
		for i in n:
			var il := maxi(i - 1, 0)
			var ir := mini(i + 1, n - 1)
			var jl := maxi(j - 1, 0)
			var jr := mini(j + 1, n - 1)
			out[j * n + i] = Vector2((heights[j * n + ir] - heights[j * n + il]) / (maxi(ir - il, 1) * cell),
				(heights[jr * n + i] - heights[jl * n + i]) / (maxi(jr - jl, 1) * cell))
	return out


## `points` with every loop cut out where the line comes back within `width` of itself
## (centre to centre: the two legs' surfaces would overlap) after running at least three
## widths away, so the far leg joins the near one where they meet.
static func merge_legs(points: PackedVector2Array, width: float) -> PackedVector2Array:
	var n := points.size()
	var along := PackedFloat32Array([0.0])
	var longest := 0.0
	for k in range(1, n):
		var step := points[k].distance_to(points[k - 1])
		along.append(along[k - 1] + step)
		longest = maxf(longest, step)
	# Segments filed by the grid square of their start: a segment within `width` of a point
	# starts within `width` plus its own length of it, so the squares round it hold them all.
	var size := width + longest
	var grid: Dictionary[Vector2i, PackedInt32Array] = {}
	for k in n - 1:
		var key := Vector2i(floori(points[k].x / size), floori(points[k].y / size))
		if not grid.has(key):
			grid[key] = PackedInt32Array()
		grid[key].append(k)
	var out := PackedVector2Array()
	var a := 0
	while a < n:
		out.append(points[a])
		# The furthest segment along that comes back near this point.
		var skip_to := -1
		var home := Vector2i(floori(points[a].x / size), floori(points[a].y / size))
		for dj in range(-1, 2):
			for di in range(-1, 2):
				for b: int in grid.get(home + Vector2i(di, dj), PackedInt32Array()):
					if b + 1 <= skip_to or along[b] - along[a] < width * 3.0:
						continue
					var near := Geometry2D.get_closest_point_to_segment(points[a], points[b], points[b + 1])
					if near.distance_to(points[a]) < width:
						skip_to = b + 1
		a = skip_to if skip_to > 0 else a + 1
	return out


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

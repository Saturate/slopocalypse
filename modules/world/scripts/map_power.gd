class_name MapPower
extends RefCounted
## Power lines on a generated map (#494), placed after the roads, sites and earthworks:
## lines of wooden poles beside the roads and tracks from a town or the city out to farms,
## and high-voltage lines of lattice pylons from a fenced substation yard outside the city to
## the towns. Kept on the map like roads: a list of lines, each its kind and the points where
## its towers stand, from its source out to what it feeds. Pure and seeded; no autoloads.
##
## Pole lines walk the way a farm's track and the road it meets take to the nearest
## settlement, a pole every so often, set back from the road's edge on one side or the other.
## A pole line that comes within a span of an earlier one ends on one of its poles, which
## takes a second, lower crossarm for it (a tap), leaving at least `branch_angle` off the
## line it joins. High-voltage lines are placed after the poles, each from a terminal of its
## own in the substation yard, facing its line: an A* search over pylon spots snapped to a
## grid, each span within the recipe's range, costing its length, each turn and each pylon.
## Every foot keeps off water, roads, settlements, sites, the yard and steep ground; no span
## passes over a settlement or a site, every span clears the ground under its lowest wire,
## and where two lines cross, one's lowest wire clears the other's highest by
## `crossing_clearance`.

## Fields the recipe's `power` section needs.
const SECTION := {
	"edge_margin": "n", "camp_clearance": "n", "crossing_clearance": "n",
	"high_voltage": {"span": "a", "max_grade": "n", "foot": "n", "keep_clear": "n", "substation": "a", "yard": "n", "yard_rise": "n",
		"terminal_inset": "n", "terminal_gap": "n", "town_reach": "n", "max_turn": "n", "turn_cost": "n", "tower_cost": "n", "towns": "n",
		"wire_height": "n", "top_height": "n", "sag": "n", "clearance": "n"},
	"poles": {"span": "a", "max_grade": "n", "setback": "n", "min_setback": "n", "sites": "a", "count": "n", "max_length": "n",
		"branch_angle": "n", "wire_height": "n", "top_height": "n", "sag": "n", "clearance": "n"},
}
## Degrees between the headings a pylon search tries, and metres between the span lengths.
const ANGLE_STEP := 5.0
const LENGTH_STEP := 10.0
## Most a high-voltage route turns away from heading straight for its terminal, degrees.
const MAX_HEADING := 150.0
## Span lengths kept at each heading a search step tries, best first: the rest are hardly
## ever the way, and pushing hundreds a step would cost more than testing the few that are.
const PER_HEADING := 3
## Metres a side of the grid search spots are snapped to: a spot is searched from once.
const SEARCH_CELL := 20.0
## How much more the distance left counts than the cost so far: a little longer way found
## at once, rather than the shortest after spreading over every spot on the map.
const GREED := 2.5
## Most spots a route search tests before giving up: one boxed in by obstacles would
## otherwise try every spot on the map.
const SEARCH_BUDGET := 1200
## How many start spots round a town, and terminals in the yard (one a side), a line tries.
const STARTS := 2
const TERMINALS := 5
## Metres between the spots tried round a town or the city, and for a terminal in the yard.
const RING_STEP := 8.0
const TERMINAL_STEP := 1.0
## Metres from a corner of the yard's terminal ring no terminal stands.
const TERMINAL_CORNER := 3.0
## Samples along a span checked for ground clearance under its wires.
const CLEARANCE_SAMPLES := 8
## Metres a track's end may lie from the road point it joins.
const JOIN_TOLERANCE := 2.0
## Metres between the steps a pole walk takes along its way.
const WALK_STEP := 1.0
## Metres past a foot's reach that must be dry: a foot on a pond's shore stands in the mud.
const WATER_MARGIN := 2.0
## Metres round a pole others keep clear of (it is about a metre across at most).
const POLE_FOOT := 0.5
## Metres a side of the tiles lines are filed under for `near`, and the furthest round them
## it answers (a wider corridor asked for is cut to this).
const TILE := 64.0
const INDEX_REACH := 32.0

var works: Earthworks
var land: WorldLand

## Each line {kind ("high_voltage" or "low_voltage"), from ("substation", a settlement, or
## "line N": a tap off line N of this list), to, points (x, z of each tower, from the source
## out), sag (the wires' dip as a share of a span's length)}.
var _lines: Array[Dictionary] = []
## The substation: {centre, yard (Rect2), level (the pad's top), base (the lowest ground
## under it), terminals (each line's first point, in line order)}; empty without one.
var _substation: Dictionary = {}
var _inside: Rect2
var _camp := Vector2.INF
var _camp_clear := 0.0
var _crossing := 0.0
## Metres a pylon's feet reach from its middle.
var _hv_foot := 0.0
var _settlements: Array[Rect2] = []
var _sites: Array[Rect2] = []
## Every span placed so far: {a, b, box (Rect2), line, low (lowest wire over the feet), top
## (highest), sag}.
var _spans: Array[Dictionary] = []
## Poles that carry a tap already.
var _tapped: Dictionary[Vector2, bool] = {}
## Tile -> the spans near it, each [from, to, high voltage or not].
var _tiles: Dictionary[Vector2i, Array] = {}
## Milliseconds the last route search took, and how many it tested, worst so far.
var slowest_route_ms := 0.0


func _init(shaped: Earthworks, places: Settlements, net: RoadNetwork, placed: MapSites, config: Dictionary, seed_value: int) -> void:
	works = shaped
	land = shaped.land
	_inside = land.bounds().grow(-float(config["edge_margin"]))
	_camp_clear = float(config["camp_clearance"])
	_crossing = float(config["crossing_clearance"])
	if places == null:
		return
	_camp = places.camp()
	for t: Dictionary in places.towns():
		_settlements.append(t["footprint"])
	if not places.city().is_empty():
		_settlements.append(places.city()["footprint"])
	# Ground set aside (the harbour by the camp) as a settlement's.
	_settlements.append_array(places.reserved())
	if placed != null:
		for s: Dictionary in placed.sites():
			_sites.append(s["footprint"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "power"])
	var hv: Dictionary = config["high_voltage"]
	_hv_foot = float(hv["foot"])
	# The yard first, so the poles keep off it; the poles before the pylons, as the pylons
	# can go round them and the poles have only their roads.
	if not places.city().is_empty() and not places.towns().is_empty():
		_substation = _pick_substation(places.city()["footprint"], places.towns(), hv)
	if net != null and placed != null:
		_poles(net, placed, config["poles"], rng)
	if not _substation.is_empty():
		_high_voltage(places, hv)
	_index()


## Every line, pole lines first.
func lines() -> Array[Dictionary]:
	return _lines


## The substation (see `_substation`), or empty when the map has none.
func substation() -> Dictionary:
	return _substation


## Where every tower of `kind` stands, once each (a tap pole is on two lines).
func towers(kind: String) -> PackedVector2Array:
	var seen: Dictionary[Vector2, bool] = {}
	for line in _lines:
		if line["kind"] == kind:
			for p: Vector2 in line["points"]:
				seen[p] = true
	return PackedVector2Array(seen.keys())


## Whether a circle of `radius` at `p` reaches a tower's feet or the substation yard.
func tower_within(p: Vector2, radius: float) -> bool:
	if not _substation.is_empty() and (_substation["yard"] as Rect2).grow(radius).has_point(p):
		return true
	for line in _lines:
		var reach := radius + (_hv_foot if line["kind"] == "high_voltage" else POLE_FOOT)
		for q: Vector2 in line["points"]:
			if q.distance_to(p) < reach:
				return true
	return false


## Whether (x, z) is within `high` metres of a high-voltage span or `low` of a pole line's
## (each cut to INDEX_REACH): ground kept free of trees, so no crown grows into the wires.
func near(x: float, z: float, high: float, low: float) -> bool:
	var entries: Variant = _tiles.get(Vector2i(floori(x / TILE), floori(z / TILE)))
	if entries == null:
		return false
	var p := Vector2(x, z)
	for e: Array in entries:
		var reach := minf(high if bool(e[2]) else low, INDEX_REACH)
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, e[0], e[1])) < reach:
			return true
	return false


## Whether a tower may stand at `p`: on the map, dry ground round it, `gap` metres clear of
## roads, settlements, sites, the yard and the camp past its foot `radius`, on ground no
## steeper than `max_grade`.
func foot_ok(p: Vector2, gap: float, max_grade: float, radius: float) -> bool:
	if not _inside.has_point(p) or p.distance_to(_camp) < _camp_clear:
		return false
	for r in _settlements:
		if r.grow(gap + radius).has_point(p):
			return false
	for r in _sites:
		if r.grow(gap + radius).has_point(p):
			return false
	if not _substation.is_empty() and (_substation["yard"] as Rect2).grow(gap + radius).has_point(p):
		return false
	if works.road_distance(p.x, p.y) < gap + radius:
		return false
	if not dry(p, radius + WATER_MARGIN):
		return false
	return works.grade(p.x, p.y) <= max_grade


## Whether there is no water at `p` or anywhere on a ring `reach` round it.
func dry(p: Vector2, reach: float) -> bool:
	if not is_nan(land.water_level(p.x, p.y)):
		return false
	for i in 8:
		var d := Vector2.from_angle(TAU * i / 8.0) * reach
		if not is_nan(land.water_level(p.x + d.x, p.y + d.y)):
			return false
	return true


## Whether wires may hang from `a` to `b` for a line of `cfg`'s kind: over no settlement or
## site (nor the yard, unless one end is a terminal in it), and with the lowest wire,
## `wire_height` over each foot and dipping `sag` of the span at its middle, at least
## `clearance` over the ground all along.
func span_ok(a: Vector2, b: Vector2, cfg: Dictionary) -> bool:
	for r in _settlements:
		if segment_meets(r, a, b):
			return false
	for r in _sites:
		if segment_meets(r, a, b):
			return false
	if not _substation.is_empty():
		var terminals: Array = _substation["terminals"]
		if not (terminals.has(a) or terminals.has(b)) and segment_meets(_substation["yard"], a, b):
			return false
	var ha := works.height(a.x, a.y) + float(cfg["wire_height"])
	var hb := works.height(b.x, b.y) + float(cfg["wire_height"])
	var dip := float(cfg["sag"]) * a.distance_to(b)
	for k in range(1, CLEARANCE_SAMPLES):
		var t := float(k) / CLEARANCE_SAMPLES
		var p := a.lerp(b, t)
		if works.height(p.x, p.y) + float(cfg["clearance"]) > lerpf(ha, hb, t) - 4.0 * dip * t * (1.0 - t):
			return false
	return true


## Whether a span from `a` to `b` of `cfg`'s kind would cross a span placed before it in plan
## view without one's lowest wire clearing the other's highest by `crossing_clearance` there.
## Spans sharing a tower do not cross.
func crosses(a: Vector2, b: Vector2, cfg: Dictionary) -> bool:
	var box := Rect2(a, Vector2.ZERO).expand(b)
	for s in _spans:
		if not box.intersects(s["box"], true):
			continue
		var c: Vector2 = s["a"]
		var d: Vector2 = s["b"]
		if a == c or a == d or b == c or b == d:
			continue
		var hit: Variant = Geometry2D.segment_intersects_segment(a, b, c, d)
		if hit == null:
			continue
		var at: Vector2 = hit
		var mine := _wire_heights(a, b, at, float(cfg["wire_height"]), float(cfg["top_height"]), float(cfg["sag"]))
		var theirs := _wire_heights(c, d, at, float(s["low"]), float(s["top"]), float(s["sag"]))
		if not (mine.x - theirs.y >= _crossing or theirs.x - mine.y >= _crossing):
			return true
	return false


## The lowest and highest wire's height at `at` on a span from `a` to `b`.
func _wire_heights(a: Vector2, b: Vector2, at: Vector2, low: float, top: float, sag: float) -> Vector2:
	var length := a.distance_to(b)
	var t := clampf(a.distance_to(at) / maxf(length, 0.001), 0.0, 1.0)
	var ground := lerpf(works.height(a.x, a.y), works.height(b.x, b.y), t)
	var dip := 4.0 * sag * length * t * (1.0 - t)
	return Vector2(ground + low - dip, ground + top - dip)


## Whether the segment from `a` to `b` passes through `rect` (clipped against it).
static func segment_meets(rect: Rect2, a: Vector2, b: Vector2) -> bool:
	return not is_nan(clip(rect, a, b).x)


## The part of the segment from `a` to `b` inside `rect` as shares [from, to] along it
## (Liang-Barsky), or NAN when it misses.
static func clip(rect: Rect2, a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	var ps: Array[float] = [-d.x, d.x, -d.y, d.y]
	var qs: Array[float] = [a.x - rect.position.x, rect.end.x - a.x, a.y - rect.position.y, rect.end.y - a.y]
	for i in 4:
		var p := ps[i]
		var q := qs[i]
		if absf(p) < 0.000001:
			if q < 0.0:
				return Vector2(NAN, NAN)
			continue
		var t := q / p
		if p < 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
		if t0 > t1:
			return Vector2(NAN, NAN)
	return Vector2(t0, t1)


## The way a tower faces (its front) at point `k` of a line through `points`: bisecting the
## line's angle there, along the line at its ends. PowerLayout turns its towers by this.
static func heading_at(points: Array, k: int) -> Vector2:
	var here := _flat(points[k])
	var dir := Vector2.ZERO
	if k > 0:
		dir += (here - _flat(points[k - 1])).normalized()
	if k < points.size() - 1:
		dir += (_flat(points[k + 1]) - here).normalized()
	# Doubling straight back: face along the way in.
	if dir.length() < 0.01 and k > 0:
		dir = here - _flat(points[k - 1])
	return dir.normalized() if dir.length() > 0.0 else Vector2(0.0, -1.0)


static func _flat(p: Variant) -> Vector2:
	if p is Vector3:
		return Vector2((p as Vector3).x, (p as Vector3).z)
	return p


func _add_line(line: Dictionary, cfg: Dictionary) -> void:
	var points: PackedVector2Array = line["points"]
	for k in range(1, points.size()):
		_spans.append({"a": points[k - 1], "b": points[k], "box": Rect2(points[k - 1], Vector2.ZERO).expand(points[k]), "line": _lines.size(),
			"low": float(cfg["wire_height"]), "top": float(cfg["top_height"]), "sag": float(cfg["sag"])})
	_lines.append(line)


## The yard outside the city the high-voltage lines start from: on rings `substation` metres
## out from the city's edge, the spot nearest the towns overall whose yard is clear of roads,
## settlements, sites and water, on ground rising no more than `yard_rise` across it.
func _pick_substation(city: Rect2, towns: Array[Dictionary], cfg: Dictionary) -> Dictionary:
	var reach: Array = cfg["substation"]
	var size := float(cfg["yard"])
	var half := size / 2.0
	var best := Vector2.INF
	var best_score := INF
	var out := float(reach[0]) + half
	while out <= float(reach[1]) + half:
		for p in _ring(city.grow(out), city.get_center()):
			var score := 0.0
			for t in towns:
				score += p.distance_to((t["footprint"] as Rect2).get_center())
			if score < best_score and _yard_ok(p, half, cfg):
				best_score = score
				best = p
		out += RING_STEP * 2.0
	if best == Vector2.INF:
		return {}
	var low := INF
	var high := -INF
	for p in _yard_samples(best, half):
		low = minf(low, works.height(p.x, p.y))
		high = maxf(high, works.height(p.x, p.y))
	return {"centre": best, "yard": Rect2(best - Vector2.ONE * half, Vector2.ONE * size), "level": high, "base": low, "terminals": [] as Array[Vector2]}


func _yard_ok(c: Vector2, half: float, cfg: Dictionary) -> bool:
	var gap := float(cfg["keep_clear"])
	var low := INF
	var high := -INF
	for p in _yard_samples(c, half):
		if not foot_ok(p, gap, INF, 0.0):
			return false
		var h := works.height(p.x, p.y)
		low = minf(low, h)
		high = maxf(high, h)
	return high - low <= float(cfg["yard_rise"])


static func _yard_samples(c: Vector2, half: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for j in 3:
		for i in 3:
			out.append(c + Vector2(i - 1, j - 1) * half)
	return out


## Spots round the edge of `rect` every `step` metres, nearest `to` first.
static func _ring(rect: Rect2, to: Vector2, step := RING_STEP) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for k in 4:
		var a := corners[k]
		var b := corners[(k + 1) % 4]
		var steps := maxi(ceili(a.distance_to(b) / step), 1)
		for s in steps:
			out.append(a.lerp(b, float(s) / steps))
	out.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.distance_squared_to(to) < q.distance_squared_to(to))
	return out


func _high_voltage(places: Settlements, cfg: Dictionary) -> void:
	var gap := float(cfg["keep_clear"])
	var foot := float(cfg["foot"])
	var grade := float(cfg["max_grade"])
	var centre: Vector2 = _substation["centre"]
	var towns: Array[Dictionary] = places.towns().duplicate()
	var names: Dictionary[Rect2, String] = {}
	for i in towns.size():
		names[towns[i]["footprint"]] = "town %d" % i
	# Nearest towns first: they take the terminals facing them.
	towns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["footprint"] as Rect2).get_center().distance_to(centre) < (b["footprint"] as Rect2).get_center().distance_to(centre))
	var terminals: Array[Vector2] = _substation["terminals"]
	for town in towns.slice(0, int(cfg["towns"])):
		var foot_print: Rect2 = town["footprint"]
		var starts: Array[Vector2] = []
		for p in _ring(foot_print.grow(float(cfg["town_reach"])), centre):
			if foot_ok(p, gap, grade, foot) and _clear_of_lines(p, foot):
				starts.append(p)
				if starts.size() >= STARTS:
					break
		var route := PackedVector2Array()
		for terminal in _terminal_spots(foot_print.get_center(), terminals, cfg).slice(0, TERMINALS):
			terminals.append(terminal)
			for start in starts:
				route = _route(start, terminal, cfg)
				if not route.is_empty():
					break
			if not route.is_empty():
				break
			terminals.pop_back()
		if route.is_empty():
			continue
		route.reverse()
		_add_line({"kind": "high_voltage", "from": "substation", "to": names[foot_print], "points": route, "sag": float(cfg["sag"])}, cfg)


## Spots for a terminal in the yard, `terminal_inset` in from its fence and `terminal_gap`
## from each other and the terminals taken: the nearest `toward` on each side of the yard,
## nearest first, then a second on each side, so a line that can't leave on the side facing
## its town (the city in the way) tries another, and two lines can share a side.
func _terminal_spots(toward: Vector2, taken: Array[Vector2], cfg: Dictionary) -> Array[Vector2]:
	var inner := (_substation["yard"] as Rect2).grow(-float(cfg["terminal_inset"]))
	var centre := inner.get_center()
	var half := inner.size / 2.0
	var gap := float(cfg["terminal_gap"])
	var rounds: Array[Array] = [[], []]
	var per_side: Dictionary[Vector2i, int] = {}
	var used := taken.duplicate()
	for p in _ring(inner, toward, TERMINAL_STEP):
		var off := p - centre
		# Not on a corner: a gantry there would reach round onto the next side's.
		if absf(off.x) > half.x - TERMINAL_CORNER and absf(off.y) > half.y - TERMINAL_CORNER:
			continue
		var side := Vector2i(signi(roundi(off.x)), 0) if absf(off.x) > absf(off.y) else Vector2i(0, signi(roundi(off.y)))
		var count: int = per_side.get(side, 0)
		if count >= rounds.size() or used.any(func(q: Vector2) -> bool: return q.distance_to(p) < gap):
			continue
		per_side[side] = count + 1
		rounds[count].append(p)
		used.append(p)
	var out: Array[Vector2] = []
	for spots: Array in rounds:
		spots.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.distance_squared_to(toward) < q.distance_squared_to(toward))
		out.append_array(spots)
	return out


## Whether `p` keeps `gap` metres off every line placed so far.
func _clear_of_lines(p: Vector2, gap: float) -> bool:
	for s in _spans:
		if (s["box"] as Rect2).grow(gap).has_point(p) and p.distance_to(Geometry2D.get_closest_point_to_segment(p, s["a"], s["b"])) < gap:
			return false
	return true


## Pylon spots from `start` to the terminal `goal`, each span `span` metres: a best-first
## search (A* with the distance left weighted by GREED) over spots snapped to SEARCH_CELL,
## each costing its span's length, `turn_cost` metres a degree it turns and `tower_cost` a
## pylon. Spots are tested when taken off the heap, not when found. Empty when no way is found
## within SEARCH_BUDGET tests.
func _route(start: Vector2, goal: Vector2, cfg: Dictionary) -> PackedVector2Array:
	var started := Time.get_ticks_usec()
	var span: Array = cfg["span"]
	var lo := float(span[0])
	var hi := float(span[1])
	var gap := float(cfg["keep_clear"])
	var foot := float(cfg["foot"])
	var grade := float(cfg["max_grade"])
	var max_turn := float(cfg["max_turn"])
	var turn_cost := float(cfg["turn_cost"])
	var tower_cost := float(cfg["tower_cost"])
	var out_of_yard := (goal - (_substation["centre"] as Vector2)).normalized()
	var pos := PackedVector2Array([start])
	var parent := PackedInt32Array([-1])
	var cost := PackedFloat32Array([0.0])
	var heading := PackedVector2Array([Vector2.ZERO])
	var heap := MinHeap.new()
	heap.push(start.distance_to(goal), 0)
	var closed: Dictionary[Vector2i, bool] = {}
	var tests := 0
	var found := -1
	while not heap.is_empty():
		var n := heap.pop()
		var p := pos[n]
		var cell := Vector2i((p / SEARCH_CELL).round())
		var is_goal := p == goal
		if n > 0:
			if not is_goal and closed.has(cell):
				continue
			tests += 1
			if tests > SEARCH_BUDGET:
				break
			if not is_goal and not (foot_ok(p, gap, grade, foot) and _clear_of_lines(p, foot)):
				# The spot is no good whichever way it is reached.
				closed[cell] = true
				continue
			var from := pos[parent[n]]
			if not span_ok(from, p, cfg) or crosses(from, p, cfg):
				continue
			if is_goal:
				found = n
				break
		closed[cell] = true
		var r := p.distance_to(goal)
		var options: Array[Vector3] = []
		# The terminal, in reach: its span leaves the yard on the terminal's side.
		if r <= hi and (r >= lo or n == 0) and _turn(heading[n], goal - p) <= max_turn and (p - goal).normalized().dot(out_of_yard) > 0.5:
			options.append(Vector3(goal.x, goal.y, cost[n] + r + turn_cost * _turn(heading[n], goal - p)))
		var toward := (goal - p).normalized()
		var angle := -MAX_HEADING
		while angle <= MAX_HEADING:
			var dir := toward.rotated(deg_to_rad(angle))
			var turn := _turn(heading[n], dir)
			if turn <= max_turn:
				# The best few lengths at each heading: a road or a slope straight ahead must
				# not crowd out every other way.
				var ahead: Array[Vector3] = []
				var length := hi
				while length >= lo:
					var q := p + dir * length
					var left := q.distance_to(goal)
					# Never closer than a span short of the goal (the last span could not be made),
					# and never losing more than a short span's worth: a way round an obstacle may
					# lead away for a while, but not back the way it came.
					if left < r + lo * 2.0 and left >= lo and not closed.has(Vector2i((q / SEARCH_CELL).round())):
						ahead.append(Vector3(q.x, q.y, cost[n] + length + turn_cost * turn + tower_cost))
					length -= LENGTH_STEP
				ahead.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z + GREED * Vector2(a.x, a.y).distance_to(goal) < b.z + GREED * Vector2(b.x, b.y).distance_to(goal))
				options.append_array(ahead.slice(0, PER_HEADING))
			angle += ANGLE_STEP
		for o in options:
			var q := Vector2(o.x, o.y)
			pos.append(q)
			parent.append(n)
			cost.append(o.z)
			heading.append((q - p).normalized())
			heap.push(o.z + GREED * q.distance_to(goal), pos.size() - 1)
	slowest_route_ms = maxf(slowest_route_ms, float(Time.get_ticks_usec() - started) / 1000.0)
	if found < 0:
		return PackedVector2Array()
	var path := PackedVector2Array()
	var at := found
	while at >= 0:
		path.append(pos[at])
		at = parent[at]
	path.reverse()
	return path


## Degrees between `heading` and `dir` (0 with no heading yet).
static func _turn(heading: Vector2, dir: Vector2) -> float:
	if heading == Vector2.ZERO:
		return 0.0
	return rad_to_deg(absf(heading.angle_to(dir)))


func _poles(net: RoadNetwork, placed: MapSites, cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	var kinds: Array = cfg["sites"]
	var ways: Array[Dictionary] = []
	var all := placed.sites()
	for i in all.size():
		if not kinds.has(all[i]["kind"]):
			continue
		var way := _way_out(net, "%s %d" % [all[i]["kind"], i])
		if not way.is_empty() and float(way["length"]) <= float(cfg["max_length"]):
			way["to"] = "%s %d" % [all[i]["kind"], i]
			ways.append(way)
	# The shortest ways first: those farms are fed, and the lines further out tap theirs.
	ways.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["length"]) < float(b["length"]))
	var fed := 0
	for way in ways:
		if fed >= int(cfg["count"]):
			break
		var first := _lines.size()
		_walk(way, cfg, rng)
		if _lines.size() > first:
			fed += 1


## The way from site `name`'s track to the settlement nearest along the roads: {points (x, z,
## from the site out), halves (each point's road half width), source (the settlement's name),
## length (metres)}; empty when the site has no track or the way meets no settlement.
static func _way_out(net: RoadNetwork, name: String) -> Dictionary:
	var roads := net.roads()
	var at := -1
	for i in roads.size():
		if roads[i]["kind"] == "track" and roads[i]["from"] == name:
			at = i
			break
	if at < 0:
		return {}
	var points := PackedVector2Array()
	var halves := PackedFloat32Array()
	var from := 0
	var to: int = (roads[at]["points"] as PackedVector2Array).size() - 1
	var source := ""
	for leg in roads.size():
		var road: Dictionary = roads[at]
		var pts: PackedVector2Array = road["points"]
		var step := 1 if to >= from else -1
		var k := from
		while true:
			if points.is_empty() or points[points.size() - 1].distance_to(pts[k]) > 0.01:
				points.append(pts[k])
				halves.append(float(road["width"]) / 2.0)
			if k == to:
				break
			k += step
		if road["kind"] != "track":
			source = str(road["from"]) if to == 0 else str(road["to"])
			break
		# A track ends on another road or track: go on along that one.
		var end := pts[to]
		var next := -1
		var next_k := -1
		var best := JOIN_TOLERANCE
		for i in roads.size():
			if i == at:
				continue
			var other: PackedVector2Array = roads[i]["points"]
			for j in other.size():
				var d := other[j].distance_to(end)
				if d < best:
					best = d
					next = i
					next_k = j
		if next < 0:
			return {}
		at = next
		var n: int = (roads[at]["points"] as PackedVector2Array).size()
		from = next_k
		if roads[at]["kind"] == "track" or roads[at]["kind"] == "highway":
			# A track goes on to where it meets a road; the highway runs from the camp to the
			# city, so its city end.
			to = n - 1
		else:
			# From a town to the city: whichever end is nearer along it.
			to = 0 if _length(roads[at]["points"], 0, next_k) <= _length(roads[at]["points"], next_k, n - 1) else n - 1
	if source.is_empty() or source == "camp":
		return {}
	return {"points": points, "halves": halves, "source": source, "length": _length(points, 0, points.size() - 1)}


static func _length(points: PackedVector2Array, a: int, b: int) -> float:
	var out := 0.0
	for k in range(mini(a, b) + 1, maxi(a, b) + 1):
		out += points[k].distance_to(points[k - 1])
	return out


## Poles along `way` from the site out, every `span` metres or so, `setback` metres off the
## edge of the road on one side or the other; taps an earlier pole line when one comes in
## reach. Adds the line when it reaches the settlement or another line.
func _walk(way: Dictionary, cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	var points: PackedVector2Array = way["points"]
	var halves: PackedFloat32Array = way["halves"]
	var along := PackedFloat32Array([0.0])
	for k in range(1, points.size()):
		along.append(along[k - 1] + points[k].distance_to(points[k - 1]))
	var total := along[along.size() - 1]
	var span: Array = cfg["span"]
	var lo := float(span[0])
	var hi := float(span[1])
	var setback := float(cfg["setback"])
	var gap := float(cfg["min_setback"])
	var grade := float(cfg["max_grade"])
	var spot := func(u: float, side: float) -> Vector2:
		return _beside(points, halves, along, u, side * setback)
	var ok := func(p: Vector2) -> bool: return foot_ok(p, gap, grade, POLE_FOOT) and _clear_of_lines(p, POLE_FOOT * 2.0)
	var poles := PackedVector2Array()
	var side := 1.0
	var u := 0.0
	while u < minf(total, hi) and poles.is_empty():
		for s: float in [side, -side]:
			var p: Vector2 = spot.call(u, s)
			if ok.call(p):
				poles.append(p)
				side = s
				break
		u += WALK_STEP * 2.0
	if poles.is_empty():
		return
	var end_at: Vector2 = points[points.size() - 1]
	var from := str(way["source"])
	var reached := false
	while true:
		var cur := poles[poles.size() - 1]
		var tap := _tap(cur, end_at, lo, hi, cfg)
		if not tap.is_empty():
			poles.append(tap["at"])
			from = "line %d" % int(tap["line"])
			reached = true
			break
		# The settlement's edge is less than a span on: the line ends here.
		if (spot.call(total, side) as Vector2).distance_to(cur) < lo:
			reached = true
			break
		var target := rng.randf_range(lo, hi)
		var lengths: Array[float] = [target]
		var l := lo
		while l <= hi:
			lengths.append(l)
			l += 5.0
		lengths.sort_custom(func(a: float, b: float) -> bool: return absf(a - target) < absf(b - target))
		var found := false
		for want in lengths:
			var v := u
			while v < total and (spot.call(v, side) as Vector2).distance_to(cur) < want:
				v += WALK_STEP
			for s: float in [side, -side]:
				var p: Vector2 = spot.call(minf(v, total), s)
				var d := p.distance_to(cur)
				if d >= lo and d <= hi and ok.call(p) and span_ok(cur, p, cfg) and not crosses(cur, p, cfg) and not _crosses_self(poles, p):
					poles.append(p)
					side = s
					u = minf(v, total)
					found = true
					break
			if found:
				break
		if not found:
			break
	if not reached or poles.size() < 2:
		return
	if from.begins_with("line "):
		_tapped[poles[poles.size() - 1]] = true
	poles.reverse()
	_add_line({"kind": "low_voltage", "from": from, "to": str(way["to"]), "points": poles, "sag": float(cfg["sag"])}, cfg)


## A pole of an earlier pole line `cur` can end on: a span away, nearer the way's end, not
## carrying a tap already, and leaving at least `branch_angle` off that line there, so the
## tap's wires do not run along the line's own. {at, line} or empty.
func _tap(cur: Vector2, end_at: Vector2, lo: float, hi: float, cfg: Dictionary) -> Dictionary:
	var least := cos(deg_to_rad(float(cfg["branch_angle"])))
	for i in _lines.size():
		var line: Dictionary = _lines[i]
		if line["kind"] != "low_voltage":
			continue
		var points: PackedVector2Array = line["points"]
		for k in points.size():
			var q := points[k]
			var d := cur.distance_to(q)
			if d < lo or d > hi or _tapped.has(q) or q.distance_to(end_at) >= cur.distance_to(end_at):
				continue
			if absf(heading_at(Array(points), k).dot((cur - q).normalized())) > least:
				continue
			if span_ok(cur, q, cfg) and not crosses(cur, q, cfg):
				return {"at": q, "line": i}
	return {}


## Whether a span from the last of `poles` to `p` would cross the line's own earlier spans.
static func _crosses_self(poles: PackedVector2Array, p: Vector2) -> bool:
	var a := poles[poles.size() - 1]
	for k in range(1, poles.size() - 1):
		if Geometry2D.segment_intersects_segment(a, p, poles[k - 1], poles[k]) != null:
			return true
	return false


## The point `u` metres along the way, `offset` metres off the edge of the road there (to the
## left for a positive offset, to the right for a negative one).
static func _beside(points: PackedVector2Array, halves: PackedFloat32Array, along: PackedFloat32Array, u: float, offset: float) -> Vector2:
	var k := along.bsearch(clampf(u, 0.0, along[along.size() - 1]))
	k = clampi(k, 1, points.size() - 1)
	var a := points[k - 1]
	var b := points[k]
	var run := maxf(along[k] - along[k - 1], 0.001)
	var t := clampf((u - along[k - 1]) / run, 0.0, 1.0)
	var at := a.lerp(b, t)
	var dir := (b - a).normalized()
	var half := lerpf(halves[k - 1], halves[k], t)
	return at + dir.orthogonal() * signf(offset) * (half + absf(offset))


func _index() -> void:
	for line in _lines:
		var points: PackedVector2Array = line["points"]
		var high: bool = line["kind"] == "high_voltage"
		for k in range(1, points.size()):
			var a := points[k - 1]
			var b := points[k]
			_file(Rect2(a, Vector2.ZERO).expand(b).grow(INDEX_REACH), [a, b, high])


func _file(box: Rect2, entry: Array) -> void:
	for tj in range(floori(box.position.y / TILE), floori(box.end.y / TILE) + 1):
		for ti in range(floori(box.position.x / TILE), floori(box.end.x / TILE) + 1):
			var key := Vector2i(ti, tj)
			if not _tiles.has(key):
				_tiles[key] = []
			_tiles[key].append(entry)

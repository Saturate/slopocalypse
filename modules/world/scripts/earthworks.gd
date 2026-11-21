class_name Earthworks
extends RefCounted
## The land as roads and settlements shape it (#428, decision 0010): each road is cut into
## hills and built up over dips to its own height across its width and shoulders, with
## banks no steeper than `bank_grade` (rise per metre) out to where they meet the land; each
## settlement (the players' camp too) stands on a level pad at its level with the same
## banks. Tunnel and bridge spans leave the land alone. The shaping is part of the height
## function, so everything that samples heights (preview, terrain, collision) agrees. Pure;
## no autoloads.

## Metres a side of the tiles road segments and pads are indexed by.
const TILE := 32.0

var land: WorldLand

var _bank: float
var _shoulder: float
var _reach: float
## A dirt track's banks: steeper and shorter than a road's, so on a hillside it is a notch
## in the slope, not a cut fanning out tens of metres.
var _track_bank: float
var _track_reach: float
## Tile key -> features near it: {road (index), segment (first point index)} or {pad (index)}.
var _tiles: Dictionary[Vector2i, Array] = {}
var _roads: Array[Dictionary] = []
var _pads: Array[Dictionary] = []


## `net` may be null (no roads); `config` is the recipe's "earthworks" section.
func _init(ground: WorldLand, places: Settlements, net: RoadNetwork, config: Dictionary, placed: MapSites = null) -> void:
	land = ground
	_bank = float(config["bank_grade"])
	_shoulder = float(config["shoulder"])
	_reach = float(config["reach"])
	_track_bank = float(config.get("track_bank_grade", _bank))
	_track_reach = float(config.get("track_reach", _reach))
	if places != null:
		for place in places.all_places():
			_add_pad(place["footprint"], float(place["level"]))
	# Sites stand on level pads of their own, as settlements do (#429).
	if placed != null:
		for site in placed.sites():
			_add_pad(site["footprint"], float(site["level"]))
	if net != null:
		for road in net.roads():
			_add_road(road)


## Height of the shaped ground at (x, z), in metres.
func height(x: float, z: float) -> float:
	var ground := land.height(x, z)
	var near: Variant = _tiles.get(_tile_of(x, z))
	if near == null:
		return ground
	var p := Vector2(x, z)
	# Each work's (level, metres outside it, bank grade, reach).
	var limits: Array[Vector4] = []
	# Each stretch of a road counts once, by its nearest segment: neighbouring segments of one
	# bend must not fight over the height. Segments of a road come in order, so a gap in the
	# indices starts another stretch (the far leg of a hairpin), which counts on its own.
	var road_at := -1
	var last_segment := -1
	var best := Vector3(0.0, 0.0, INF)
	for f: Dictionary in near:
		if f.has("pad"):
			var pad: Dictionary = _pads[int(f["pad"])]
			var e := _outside(pad["rect"], p)
			# On a pad it is level, whatever banks of other works reach in: roads only meet
			# pads at their edges.
			if e == 0.0:
				return float(pad["level"])
			if e <= _reach:
				limits.append(Vector4(float(pad["level"]), e, _bank, _reach))
			continue
		var road: Dictionary = _roads[int(f["road"])]
		if _in_span(road, p):
			continue
		var k := int(f["segment"])
		var at := _on_segment(road, k, p, bool(f["open_start"]), bool(f["open_end"]))
		if is_nan(at.x):
			continue
		var e := maxf(at.x - float(road["half"]), 0.0)
		if e > float(road["reach"]):
			continue
		if int(f["road"]) != road_at or k > last_segment + 2:
			if best.z < INF:
				limits.append(Vector4(best.x, best.y, float(_roads[road_at]["bank"]), float(_roads[road_at]["reach"])))
			best = Vector3(0.0, 0.0, INF)
			road_at = int(f["road"])
		last_segment = k
		# By distance to the centre line, not by `e`: across the road's width every segment
		# nearby has e = 0, and only the nearest has the right height.
		if at.x < best.z:
			best = Vector3(at.y, e, at.x)
	if best.z < INF:
		limits.append(Vector4(best.x, best.y, float(_roads[road_at]["bank"]), float(_roads[road_at]["reach"])))
	if limits.is_empty():
		return ground
	var lo := -INF
	var hi := INF
	var hold := 0.0
	for limit in limits:
		lo = maxf(lo, limit.x - limit.z * limit.y)
		hi = minf(hi, limit.x + limit.z * limit.y)
		# A bank that has not met the land by its reach (a hillside steeper than the bank)
		# eases into it over the last quarter instead of ending in a cliff.
		hold = maxf(hold, 1.0 - smoothstep(limit.w * 0.75, limit.w, limit.y))
	# Where two works disagree (a road climbing past a pad) the ground runs between them;
	# the middle is continuous with the clamp on both sides, so it never steps.
	var shaped := clampf(ground, lo, hi) if lo <= hi else (lo + hi) / 2.0
	return lerpf(ground, shaped, hold)


## Metres from (x, z) to the edge of the nearest road or track (0 or less on it), or INF when
## none is within its earthworks' reach. Over a tunnel or under a bridge counts as off it.
func road_distance(x: float, z: float) -> float:
	var near: Variant = _tiles.get(_tile_of(x, z))
	if near == null:
		return INF
	var p := Vector2(x, z)
	var best := INF
	for f: Dictionary in near:
		if f.has("pad"):
			continue
		var road: Dictionary = _roads[int(f["road"])]
		var at := _on_segment(road, int(f["segment"]), p, true, true)
		best = minf(best, at.x - float(road["edge"]))
	return best


## Rise per metre of the shaped ground at (x, z).
func grade(x: float, z: float) -> float:
	var d := WorldLand.GRADE_STEP
	return Vector2(height(x + d, z) - height(x - d, z), height(x, z + d) - height(x, z - d)).length() / (2.0 * d)


func _add_pad(rect: Rect2, level: float) -> void:
	var index := _pads.size()
	_pads.append({"rect": rect.grow(_shoulder), "level": level})
	_index(rect.grow(_shoulder + _reach), {"pad": index})


func _add_road(road: Dictionary) -> void:
	var points: PackedVector2Array = road["points"]
	var skip := PackedByteArray()
	skip.resize(points.size())
	for span: Vector2i in (road["tunnels"] as Array) + (road["bridges"] as Array):
		for i in range(span.x, span.y + 1):
			skip[i] = 1
	var index := _roads.size()
	var half := float(road["width"]) / 2.0 + _shoulder
	var track: bool = road["kind"] == "track"
	var reach := _track_reach if track else _reach
	# Between a tunnel's or bridge's two mouths the road shapes nothing, not even with the
	# banks of the cuts leading up to them: each span is kept as the slab between the planes
	# across its mouths, facing into it.
	var slabs: Array[PackedVector2Array] = []
	var last := points.size() - 1
	for span: Vector2i in (road["tunnels"] as Array) + (road["bridges"] as Array):
		var a := points[maxi(span.x - 1, 0)]
		var b := points[mini(span.y + 1, last)]
		var into_a := (points[mini(span.x, last)] - a).normalized()
		var into_b := (points[maxi(span.y, 0)] - b).normalized()
		slabs.append(PackedVector2Array([a, into_a, b, into_b]))
	_roads.append({"points": points, "heights": road["heights"], "half": half, "edge": float(road["width"]) / 2.0, "slabs": slabs,
		"bank": _track_bank if track else _bank, "reach": reach})
	for k in points.size() - 1:
		# A segment touching a tunnel or bridge sample is left out: the land stays as it is
		# over a tunnel and under a bridge.
		if skip[k] == 1 or skip[k + 1] == 1:
			continue
		# A segment's rounded end shapes the ground past it, except where a tunnel or bridge
		# goes on from there: the hill over a tunnel mouth stays, and so does the gap under
		# a bridge.
		var open_start := k == 0 or skip[k - 1] == 0
		var open_end := k + 2 >= points.size() or skip[k + 2] == 0
		var box := Rect2(points[k], Vector2.ZERO).expand(points[k + 1])
		_index(box.grow(half + reach), {"road": index, "segment": k, "open_start": open_start, "open_end": open_end})


func _index(box: Rect2, feature: Dictionary) -> void:
	var from := _tile_of(box.position.x, box.position.y)
	var to := _tile_of(box.end.x, box.end.y)
	for tj in range(from.y, to.y + 1):
		for ti in range(from.x, to.x + 1):
			var key := Vector2i(ti, tj)
			if not _tiles.has(key):
				_tiles[key] = []
			_tiles[key].append(feature)


func _tile_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / TILE), floori(z / TILE))


## Distance from the road's centre line along segment `k` to `p`, and the road's height
## there; NAN when `p` lies past an end that is not open.
static func _on_segment(road: Dictionary, k: int, p: Vector2, open_start: bool, open_end: bool) -> Vector2:
	var points: PackedVector2Array = road["points"]
	var heights: PackedFloat32Array = road["heights"]
	var a := points[k]
	var b := points[k + 1]
	var ab := b - a
	var t := (p - a).dot(ab) / maxf(ab.length_squared(), 1e-6)
	if (t < 0.0 and not open_start) or (t > 1.0 and not open_end):
		return Vector2(NAN, 0.0)
	t = clampf(t, 0.0, 1.0)
	return Vector2(p.distance_to(a + ab * t), lerpf(heights[k], heights[k + 1], t))


## Whether `p` lies between the mouths of one of the road's tunnels or bridges.
static func _in_span(road: Dictionary, p: Vector2) -> bool:
	for slab: PackedVector2Array in road["slabs"]:
		if (p - slab[0]).dot(slab[1]) > 0.0 and (p - slab[2]).dot(slab[3]) > 0.0:
			return true
	return false


## How far `p` lies outside `rect` (0 inside).
static func _outside(rect: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(rect.position.x - p.x, p.x - rect.end.x), 0.0)
	var dz := maxf(maxf(rect.position.y - p.y, p.y - rect.end.y), 0.0)
	return Vector2(dx, dz).length()

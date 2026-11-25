class_name Settlements
extends RefCounted
## Where people live on a map (#428, decision 0010): the city on the largest square of flat
## ground its zone holds, a few towns on other flat ground apart from it, and the players'
## camp outside them all near an edge, on a square pad of its own (#420, decision 0014).
## Each settlement is a compact square footprint (later stages lay out streets and terraces
## inside it, #430), a level (the ground's middle height there) and a connector in the
## middle of each side where roads may arrive. On an island (#454) the camp stands near the
## sea with a harbour spot reserved on the shore beside it, where a jetty runs out to water
## deep enough for a boat. Pure and seeded through its zones; no autoloads.

## Camp spots tried, best first, before settling for one without a harbour.
const CAMP_TRIES := 64
## Metres between checks along the shore and out along a jetty.
const SHORE_STEP := 0.5
const JETTY_STEP := 2.0
## Metres either side of a jetty's root the shore is measured over for how steep it is.
const ROOT_SPAN := 3.0


var zones: LandZones

var _city: Dictionary = {}
var _towns: Array[Dictionary] = []
var _camp := Vector2.ZERO
var _camp_place: Dictionary = {}
var _harbour: Dictionary = {}
var _edge_margin := 0


func _init(map_zones: LandZones, config: Dictionary) -> void:
	zones = map_zones
	_edge_margin = ceili(float(config["edge_margin"]) / zones.cell_size())
	var city_cfg: Dictionary = config["city"]
	var town_cfg: Dictionary = config["town"]
	var candidates := _squares(_use_kinds(StringName(str(city_cfg["use"]))), float(city_cfg["size"]))
	if not candidates.is_empty():
		var found: Dictionary = candidates[0]
		# The city the city module builds is `max_size` across: its footprint is that square
		# in the middle of the largest one, not all of it (#472).
		if city_cfg.has("max_size"):
			var foot: Rect2 = found["footprint"]
			var side := minf(foot.size.x, float(city_cfg["max_size"]))
			found = found.duplicate()
			found["footprint"] = Rect2(foot.get_center() - Vector2.ONE * side / 2.0, Vector2.ONE * side)
		_city = _settlement(&"city", found)
	for found: Dictionary in _squares(_use_kinds(StringName(str(town_cfg["use"]))), float(town_cfg["size"])):
		if _towns.size() >= int(town_cfg["max"]):
			break
		var centre: Vector2 = (found["footprint"] as Rect2).get_center()
		var places: Array[Dictionary] = _towns.duplicate()
		if not _city.is_empty():
			places.append(_city)
		if places.any(func(p: Dictionary) -> bool: return centre.distance_to(p["centre"]) < float(town_cfg["spacing"])):
			continue
		_towns.append(_settlement(&"town", found))
	var camp_cfg: Dictionary = config["camp"]
	var side := float(camp_cfg["size"])
	if zones.land.has_coast() and camp_cfg.has("sea") and config.get("harbour") is Dictionary:
		_camp = _pick_coast_camp(float(camp_cfg["clearance"]), camp_cfg["sea"], config["harbour"], side)
	else:
		_camp = _pick_camp(float(camp_cfg["clearance"]))
	var zone: Dictionary = zones.zone_at(_camp.x, _camp.y)
	_camp_place = _settlement(&"camp", {"zone": int(zone.get("id", -1)), "footprint": Rect2(_camp - Vector2.ONE * side / 2.0, Vector2.ONE * side)})


## The city: {kind, centre, footprint (Rect2 on x, z), level, connectors (Vector3 per side),
## zone (id)}; empty if the map has nowhere for one.
func city() -> Dictionary:
	return _city


func towns() -> Array[Dictionary]:
	return _towns


## Where the players' camp stands (x, z): the middle of its pad.
func camp() -> Vector2:
	return _camp


## The camp's pad as a settlement ({kind, centre, footprint, level, connectors, zone, half}):
## the earthworks level it, the highway leaves from its side nearest the city.
func camp_place() -> Dictionary:
	return _camp_place


## The harbour spot by the camp on an island (#454), where a jetty goes: {root (on the
## shoreline, at sea level), facing (unit, x and z: straight out to sea), length (metres of
## jetty out to water deep enough), end (root plus facing times length, at sea level), depth
## (metres of water at the end), footprint (Rect2 round the root: ground kept free of roads,
## sites, power and trees)}; empty without a coast or where no shore near the camp suits.
func harbour() -> Dictionary:
	return _harbour


## Ground set aside that roads, sites, power and trees keep out of, besides the settlements:
## the harbour's footprint.
func reserved() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if not _harbour.is_empty():
		out.append(_harbour["footprint"])
	return out


## The city, the towns and the camp: every footprint roads and sites keep out of.
func all_places() -> Array[Dictionary]:
	var out: Array[Dictionary] = _towns.duplicate()
	if not _city.is_empty():
		out.append(_city)
	if not _camp_place.is_empty():
		out.append(_camp_place)
	return out


func _use_kinds(use: StringName) -> Array:
	var uses: Dictionary = zones.config()["uses"]
	var spec: Dictionary = uses.get(String(use), {})
	return spec.get("kinds", [])


## For each zone of `kinds`, the largest square of its cells at least `size` metres a side:
## [{zone, footprint}], largest first.
func _squares(kinds: Array, size: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cell := zones.cell_size()
	for zone: Dictionary in zones.zones(&""):
		if not kinds.has(zone["kind"]) or float(zone["area"]) < size * size:
			continue
		var square := _largest_square(int(zone["id"]))
		if square.size.x >= size:
			out.append({"zone": int(zone["id"]), "footprint": square})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["footprint"] as Rect2).size.x > (b["footprint"] as Rect2).size.x)
	return out


## The largest square of cells all in zone `id` (the classic dynamic programme over the grid:
## each cell holds the side of the largest square ending at it).
func _largest_square(id: int) -> Rect2:
	var n := zones.side()
	var cell := zones.cell_size()
	var run := PackedInt32Array()
	run.resize(n * n)
	var best := 0
	var best_end := Vector2i.ZERO
	for j in n:
		for i in n:
			# Room round every settlement for the roads in and its outskirts.
			var inside := i >= _edge_margin and j >= _edge_margin and i < n - _edge_margin and j < n - _edge_margin
			if not inside or zones.zone_id_at_cell(i, j) != id:
				continue
			var k := j * n + i
			var v := 1
			if i > 0 and j > 0:
				v = 1 + mini(run[k - 1], mini(run[k - n], run[k - n - 1]))
			run[k] = v
			if v > best:
				best = v
				best_end = Vector2i(i, j)
	var corner := zones.cell_centre(best_end.x - best + 1, best_end.y - best + 1) - Vector2(cell, cell) / 2.0
	return Rect2(corner, Vector2(best, best) * cell)


func _settlement(kind: StringName, found: Dictionary) -> Dictionary:
	var foot: Rect2 = found["footprint"]
	var land := zones.land
	var heights: Array[float] = []
	for i in 5:
		for j in 5:
			var p := foot.position + foot.size * (Vector2(i, j) + Vector2(0.5, 0.5)) / 5.0
			heights.append(land.height(p.x, p.y))
	heights.sort()
	var level := heights[heights.size() / 2]
	var c := foot.get_center()
	var half := foot.size / 2.0
	var connectors: Array[Vector3] = [
		Vector3(c.x, level, foot.position.y), Vector3(c.x, level, foot.end.y),
		Vector3(foot.position.x, level, c.y), Vector3(foot.end.x, level, c.y),
	]
	return {"kind": String(kind), "centre": c, "footprint": foot, "level": level, "connectors": connectors, "zone": int(found["zone"]), "half": half}


## The zones' spawn when it is clear of every settlement by `clearance`; else the flattest
## open or flat spot in the same edge band that is.
func _pick_camp(clearance: float) -> Vector2:
	var places: Array[Dictionary] = _towns.duplicate()
	if not _city.is_empty():
		places.append(_city)
	var clear := func(p: Vector2) -> bool:
		return not places.any(func(s: Dictionary) -> bool: return (s["footprint"] as Rect2).grow(clearance).has_point(p))
	var spawn := zones.spawn()
	if clear.call(spawn):
		return spawn
	var cfg := zones.config()
	var b := zones.land.bounds()
	var best := spawn
	var best_grade := INF
	for j in zones.side():
		for i in zones.side():
			var c := zones.cell_centre(i, j)
			var to_edge := minf(minf(c.x - b.position.x, b.end.x - c.x), minf(c.y - b.position.y, b.end.y - c.y))
			if to_edge < float(cfg["spawn_margin"]) or to_edge > float(cfg["spawn_edge"]) or not clear.call(c):
				continue
			var kind := str(zones.zone_at(c.x, c.y)["kind"])
			if kind != "flat" and kind != "open":
				continue
			var grade := zones.land.grade(c.x, c.y)
			if grade < best_grade:
				best_grade = grade
				best = c
	return best


## On an island: the best spot for the camp `sea` [nearest, furthest] metres from the sea on
## flat or open ground of the main island, clear of every settlement by `clearance`, with a
## harbour spot on the shore within reach (see `_find_harbour`); the flattest such spot in
## the largest such ground first, as `LandZones` picks its spawn. Without a spot that has a
## harbour, the best spot without one; without any, as on a map with no coast.
func _pick_coast_camp(clearance: float, sea: Array, harbour_cfg: Dictionary, side: float) -> Vector2:
	var places: Array[Dictionary] = _towns.duplicate()
	if not _city.is_empty():
		places.append(_city)
	var land := zones.land
	var near := float(sea[0])
	var far := float(sea[1])
	var spots: Array[Vector3] = []
	for j in zones.side():
		for i in zones.side():
			var c := zones.cell_centre(i, j)
			var to_sea := zones.sea_distance(c.x, c.y)
			if to_sea < near or to_sea > far:
				continue
			if places.any(func(p: Dictionary) -> bool: return (p["footprint"] as Rect2).grow(clearance).has_point(c)):
				continue
			# The whole pad on usable ground, not just its middle.
			var usable := true
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2.ZERO]:
				var p := c + corner * side / 2.0
				var kind := str(zones.zone_at(p.x, p.y).get("kind", ""))
				if kind != "flat" and kind != "open":
					usable = false
					break
			if not usable:
				continue
			var zone: Dictionary = zones.zone_at(c.x, c.y)
			spots.append(Vector3(c.x, c.y, land.grade(c.x, c.y) - minf(float(zone["area"]), 20000.0) / 2.0e6))
	if spots.is_empty():
		return _pick_camp(clearance)
	spots.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z < b.z if a.z != b.z else (a.x < b.x if a.x != b.x else a.y < b.y))
	for k in mini(spots.size(), CAMP_TRIES):
		var at := Vector2(spots[k].x, spots[k].y)
		var found := _find_harbour(at, side, harbour_cfg, places)
		if not found.is_empty():
			_harbour = found
			return at
	return Vector2(spots[0].x, spots[0].y)


## The harbour spot nearest the camp at `camp` (its pad `side` metres a side): where the main
## island's shore meets the sea within `reach` metres, the ground at the waterline no steeper
## than `max_grade`, and a jetty straight out to sea (facing down the shore's slope) reaches
## water `min_depth` deep within `length` [shortest, longest] metres over nothing but sea. Its
## footprint (`size` metres a side round the root) keeps off the camp pad and `places`.
## Empty when no shore in reach suits.
func _find_harbour(camp: Vector2, side: float, cfg: Dictionary, places: Array[Dictionary]) -> Dictionary:
	var land := zones.land
	var reach := float(cfg["reach"])
	var lengths: Array = cfg["length"]
	var min_depth := float(cfg["min_depth"])
	var max_grade := float(cfg["max_grade"])
	var size := float(cfg["size"])
	var pad := Rect2(camp - Vector2.ONE * side / 2.0, Vector2.ONE * side)
	var cell := zones.cell_size()
	var span := ceili(reach / cell) + 1
	var origin := zones.cell_centre(0, 0)
	var ci := roundi((camp.x - origin.x) / cell)
	var cj := roundi((camp.y - origin.y) / cell)
	var best: Dictionary = {}
	var best_score := INF
	for j in range(cj - span, cj + span + 1):
		for i in range(ci - span, ci + span + 1):
			if not zones.is_sea_cell(i, j):
				continue
			var sea_c := zones.cell_centre(i, j)
			if sea_c.distance_to(camp) > reach:
				continue
			for d: Vector2i in LandZones.SIDES:
				var li := i + d.x
				var lj := j + d.y
				if li < 0 or lj < 0 or li >= zones.side() or lj >= zones.side() or zones.is_sea_cell(li, lj):
					continue
				var land_c := zones.cell_centre(li, lj)
				if str(zones.zone_at(land_c.x, land_c.y).get("kind", "")) == "islet":
					continue
				var spot := _harbour_at(land_c, sea_c, lengths, min_depth, max_grade, size)
				if spot.is_empty():
					continue
				var foot: Rect2 = spot["footprint"]
				if foot.intersects(pad) or places.any(func(p: Dictionary) -> bool: return (p["footprint"] as Rect2).intersects(foot)):
					continue
				var score := (spot["root"] as Vector3).distance_to(Vector3(camp.x, land.sea_level, camp.y)) + float(spot["length"])
				if score < best_score:
					best_score = score
					best = spot
	return best


## The harbour spot where the shoreline crosses from `land_c` towards `sea_c`, or empty when
## the ground there is too steep or no jetty reaches deep enough water over open sea.
func _harbour_at(land_c: Vector2, sea_c: Vector2, lengths: Array, min_depth: float, max_grade: float, size: float) -> Dictionary:
	var land := zones.land
	var sea := land.sea_level
	var root := Vector2.INF
	var steps := ceili(land_c.distance_to(sea_c) / SHORE_STEP)
	for k in steps + 1:
		var p := land_c.lerp(sea_c, float(k) / steps)
		if land.land_height(p.x, p.y) < sea:
			root = p
			break
	if root == Vector2.INF:
		return {}
	var g := Vector2(land.land_height(root.x + ROOT_SPAN, root.y) - land.land_height(root.x - ROOT_SPAN, root.y),
		land.land_height(root.x, root.y + ROOT_SPAN) - land.land_height(root.x, root.y - ROOT_SPAN)) / (2.0 * ROOT_SPAN)
	if g.length() > max_grade or g.length() < 0.0001:
		return {}
	var facing := -g.normalized()
	var length := float(lengths[0])
	while length <= float(lengths[1]):
		var end := root + facing * length
		var depth := sea - land.land_height(end.x, end.y)
		if depth >= min_depth:
			# Open water all the way out: no rock or sandbar the jetty would cross.
			var d := JETTY_STEP
			while d <= length and land.is_sea(root.x + facing.x * d, root.y + facing.y * d):
				d += JETTY_STEP
			if d <= length:
				return {}
			return {"root": Vector3(root.x, sea, root.y), "facing": facing, "length": length, "end": Vector3(end.x, sea, end.y), "depth": depth,
				"footprint": Rect2(root - Vector2.ONE * size / 2.0, Vector2.ONE * size)}
		length += JETTY_STEP
	return {}

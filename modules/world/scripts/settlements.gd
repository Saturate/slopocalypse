class_name Settlements
extends RefCounted
## Where people live on a map (#428, decision 0010): the city on the largest square of flat
## ground its zone holds, a few towns on other flat ground apart from it, and the players'
## camp outside them all near an edge, on a square pad of its own (#420, decision 0014).
## Each settlement is a compact square footprint (later stages lay out streets and terraces
## inside it, #430), a level (the ground's middle height there) and a connector in the
## middle of each side where roads may arrive. Pure and seeded through its zones; no
## autoloads.


var zones: LandZones

var _city: Dictionary = {}
var _towns: Array[Dictionary] = []
var _camp := Vector2.ZERO
var _camp_place: Dictionary = {}
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
	_camp = _pick_camp(float(camp_cfg["clearance"]))
	var side := float(camp_cfg["size"])
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

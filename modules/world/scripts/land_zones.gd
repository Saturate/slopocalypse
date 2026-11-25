class_name LandZones
extends RefCounted
## The land read as places (#427, decision 0010): every `cell` metres of the map gets a kind
## (water, wetland, slope, hilltop, forest, flat, open), touching cells of one kind make a
## zone; on an island map (#454) land off the main island is an islet, never used, and each use (city, town, farm, camp, hilltop) can ask for the best zone that suits
## it. Later stages place settlements, roads and sites from this. Pure and seeded through
## its land; read-only once built. No autoloads: tools use it too.

## In the order a cell is tested: the first that fits is its kind. An islet is any land the
## main island's ground does not reach, whatever it would be otherwise.
const KINDS: Array[String] = ["water", "wetland", "slope", "hilltop", "forest", "flat", "open", "islet"]

var land: WorldLand

var _cfg: Dictionary
var _cell := 16.0
var _side := 0
## Per cell, the index of its zone in `_zones`.
var _zone_of := PackedInt32Array()
## Each {id, kind, area (square metres), centre (x, z), cells, grade (mean rise per metre)}.
var _zones: Array[Dictionary] = []
var _spawn := Vector2.ZERO
## Per cell on an island map: 1 for the sea, and metres to the nearest sea cell (INF on a map
## without a coast).
var _sea := PackedByteArray()
var _sea_distance := PackedFloat32Array()
## Each cell's rise per metre, worked out once while classifying (0 under water).
var _grades := PackedFloat32Array()


func _init(world: WorldLand, config: Dictionary) -> void:
	land = world
	_cfg = config
	_cell = float(config["cell"])
	_side = int(ceil(land.size / _cell))
	var kinds := _classify()
	if land.has_coast():
		_mark_islets(kinds)
		_measure_sea_distance()
	_merge(kinds)
	_spawn = _pick_spawn()


## The zone (x, z) lies in, or empty off the map.
func zone_at(x: float, z: float) -> Dictionary:
	var k := _cell_index(x, z)
	return _zones[_zone_of[k]] if k >= 0 else {}


## Every zone of `kind` (all of them for an empty kind), largest first.
func zones(kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for zone in _zones:
		if kind == &"" or zone["kind"] == String(kind):
			out.append(zone)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["area"]) > float(b["area"]))
	return out


## The best zone for `use` (zones.uses in the recipe): of the kinds it may go on and at
## least its `min_area`, the largest; empty when none fits.
func best(use: StringName) -> Dictionary:
	var spec: Dictionary = (_cfg["uses"] as Dictionary).get(String(use), {})
	if spec.is_empty():
		return {}
	var kinds: Array = spec["kinds"]
	var found: Dictionary = {}
	for zone in _zones:
		if not kinds.has(zone["kind"]) or float(zone["area"]) < float(spec["min_area"]):
			continue
		if found.is_empty() or float(zone["area"]) > float(found["area"]):
			found = zone
	return found


## The `zones` block of the recipe this was built from.
func config() -> Dictionary:
	return _cfg


## Metres a zone cell covers, and cells along a side.
func cell_size() -> float:
	return _cell


func side() -> int:
	return _side


## The zone id of cell (i, j), or -1 off the map.
func zone_id_at_cell(i: int, j: int) -> int:
	if i < 0 or j < 0 or i >= _side or j >= _side:
		return -1
	return _zone_of[j * _side + i]


## The middle of cell (i, j) on the ground (x, z).
func cell_centre(i: int, j: int) -> Vector2:
	return _cell_centre(j * _side + i)


## Where the players' camp goes: flat dry ground between `spawn_margin` and `spawn_edge`
## metres in from the map's edge, or on an island that far in from the sea.
func spawn() -> Vector2:
	return _spawn


## Metres from (x, z) to the sea, on the zone grid (0 at sea, INF without a coast or off the
## map).
func sea_distance(x: float, z: float) -> float:
	var k := _cell_index(x, z)
	return _sea_distance[k] if k >= 0 and not _sea_distance.is_empty() else INF


## Whether cell (i, j) is sea.
func is_sea_cell(i: int, j: int) -> bool:
	return not _sea.is_empty() and i >= 0 and j >= 0 and i < _side and j < _side and _sea[j * _side + i] == 1


func _cell_index(x: float, z: float) -> int:
	var b := land.bounds()
	var i := floori((x - b.position.x) / _cell)
	var j := floori((z - b.position.y) / _cell)
	if i < 0 or j < 0 or i >= _side or j >= _side:
		return -1
	return j * _side + i


func _cell_centre(k: int) -> Vector2:
	var b := land.bounds()
	return b.position + Vector2((k % _side + 0.5) * _cell, (k / _side + 0.5) * _cell)


func _classify() -> PackedByteArray:
	var kinds := PackedByteArray()
	kinds.resize(_side * _side)
	var wet := PackedByteArray()
	wet.resize(_side * _side)
	_grades.resize(_side * _side)
	if land.has_coast():
		_sea.resize(_side * _side)
	for k in _side * _side:
		var c := _cell_centre(k)
		wet[k] = 1 if not is_nan(land.water_level(c.x, c.y)) else 0
		if not _sea.is_empty() and land.is_sea(c.x, c.y):
			_sea[k] = 1
	var reach := ceili(float(_cfg["wet_distance"]) / _cell)
	var ring := float(_cfg["hilltop_ring"])
	for k in _side * _side:
		var c := _cell_centre(k)
		if wet[k] == 1:
			kinds[k] = KINDS.find("water")
			continue
		var kind := "open"
		var grade := land.grade(c.x, c.y)
		_grades[k] = grade
		if _near(wet, k, reach):
			kind = "wetland"
		elif grade > float(_cfg["slope_grade"]):
			kind = "slope"
		elif _rise(c, ring) > float(_cfg["hilltop_rise"]):
			kind = "hilltop"
		elif land.forest(c.x, c.y) > float(_cfg["forest_cutoff"]):
			kind = "forest"
		elif grade < float(_cfg["flat_grade"]):
			kind = "flat"
		kinds[k] = KINDS.find(kind)
	return kinds


## Whether a wet cell lies within `reach` cells of cell `k`.
func _near(wet: PackedByteArray, k: int, reach: int) -> bool:
	var i := k % _side
	var j := k / _side
	for dj in range(-reach, reach + 1):
		for di in range(-reach, reach + 1):
			var ni := i + di
			var nj := j + dj
			if ni >= 0 and nj >= 0 and ni < _side and nj < _side and wet[nj * _side + ni] == 1:
				return true
	return false


## How far `c` stands above the ground `ring` metres round it (the mean of eight points).
func _rise(c: Vector2, ring: float) -> float:
	var around := 0.0
	for a in 8:
		var p := c + Vector2.from_angle(TAU * a / 8.0) * ring
		around += land.height(p.x, p.y)
	return land.height(c.x, c.y) - around / 8.0


## Land the main island does not reach becomes islet: the largest stretch of cells joined
## over anything but the sea (a pond does not cut it in two) is the main island.
func _mark_islets(kinds: PackedByteArray) -> void:
	var island := PackedInt32Array()
	island.resize(_side * _side)
	island.fill(-1)
	var sizes: Array[int] = []
	for start in _side * _side:
		if _sea[start] == 1 or island[start] >= 0:
			continue
		var id := sizes.size()
		var count := 0
		var stack: Array[int] = [start]
		island[start] = id
		while not stack.is_empty():
			var k: int = stack.pop_back()
			count += 1
			for d: Vector2i in SIDES:
				var ni := k % _side + d.x
				var nj := k / _side + d.y
				if ni < 0 or nj < 0 or ni >= _side or nj >= _side:
					continue
				var nk := nj * _side + ni
				if _sea[nk] == 0 and island[nk] < 0:
					island[nk] = id
					stack.append(nk)
		sizes.append(count)
	var main := sizes.find(sizes.max()) if not sizes.is_empty() else -1
	var islet := KINDS.find("islet")
	for k in _side * _side:
		if island[k] >= 0 and island[k] != main and KINDS[kinds[k]] != "water":
			kinds[k] = islet


## Each cell's metres to the nearest sea cell: a spread over the grid from every sea cell,
## a cell or a diagonal at a time.
func _measure_sea_distance() -> void:
	_sea_distance.resize(_side * _side)
	_sea_distance.fill(INF)
	var heap := MinHeap.new()
	for k in _side * _side:
		if _sea[k] == 1:
			_sea_distance[k] = 0.0
			heap.push(0.0, k)
	while not heap.is_empty():
		var k := heap.pop()
		var here := _sea_distance[k]
		for d: Vector2i in AROUND:
			var ni := k % _side + d.x
			var nj := k / _side + d.y
			if ni < 0 or nj < 0 or ni >= _side or nj >= _side:
				continue
			var nk := nj * _side + ni
			var step := _cell * (1.4142135 if d.x != 0 and d.y != 0 else 1.0)
			if here + step < _sea_distance[nk]:
				_sea_distance[nk] = here + step
				heap.push(here + step, nk)


func _merge(kinds: PackedByteArray) -> void:
	_zone_of.resize(_side * _side)
	_zone_of.fill(-1)
	var area := _cell * _cell
	for start in _side * _side:
		if _zone_of[start] >= 0:
			continue
		var id := _zones.size()
		var kind := kinds[start]
		var cells: Array[int] = []
		var stack: Array[int] = [start]
		_zone_of[start] = id
		var sum := Vector2.ZERO
		var grade := 0.0
		while not stack.is_empty():
			var k: int = stack.pop_back()
			cells.append(k)
			var c := _cell_centre(k)
			sum += c
			grade += _grades[k]
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni := k % _side + d.x
				var nj := k / _side + d.y
				if ni < 0 or nj < 0 or ni >= _side or nj >= _side:
					continue
				var nk := nj * _side + ni
				if _zone_of[nk] < 0 and kinds[nk] == kind:
					_zone_of[nk] = id
					stack.append(nk)
		_zones.append({"id": id, "kind": KINDS[kind], "area": cells.size() * area, "centre": sum / cells.size(), "cells": cells, "grade": grade / cells.size()})


func _pick_spawn() -> Vector2:
	var b := land.bounds()
	var margin := float(_cfg["spawn_margin"])
	var edge := float(_cfg["spawn_edge"])
	var best := Vector2.ZERO
	var best_grade := INF
	for k in _side * _side:
		var c := _cell_centre(k)
		var to_edge := _sea_distance[k] if not _sea_distance.is_empty() else minf(minf(c.x - b.position.x, b.end.x - c.x), minf(c.y - b.position.y, b.end.y - c.y))
		if to_edge < margin or to_edge > edge:
			continue
		var zone := _zones[_zone_of[k]]
		if zone["kind"] != "flat" and zone["kind"] != "open":
			continue
		# The flattest spot in the largest flat ground: a camp needs room round it.
		var score := land.grade(c.x, c.y) - minf(float(zone["area"]), 20000.0) / 2.0e6
		if score < best_grade:
			best_grade = score
			best = c
	return best


const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const AROUND: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

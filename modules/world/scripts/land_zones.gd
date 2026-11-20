class_name LandZones
extends RefCounted
## The land read as places (#427, decision 0010): every `cell` metres of the map gets a kind
## (water, wetland, slope, hilltop, forest, flat, open), touching cells of one kind make a
## zone, and each use (city, town, farm, camp, hilltop) can ask for the best zone that suits
## it. Later stages place settlements, roads and sites from this. Pure and seeded through
## its land; read-only once built. No autoloads: tools use it too.

## In the order a cell is tested: the first that fits is its kind.
const KINDS: Array[String] = ["water", "wetland", "slope", "hilltop", "forest", "flat", "open"]

var land: WorldLand

var _cfg: Dictionary
var _cell := 16.0
var _side := 0
## Per cell, the index of its zone in `_zones`.
var _zone_of := PackedInt32Array()
## Each {id, kind, area (square metres), centre (x, z), cells, grade (mean rise per metre)}.
var _zones: Array[Dictionary] = []
var _spawn := Vector2.ZERO


func _init(world: WorldLand, config: Dictionary) -> void:
	land = world
	_cfg = config
	_cell = float(config["cell"])
	_side = int(ceil(land.size / _cell))
	var kinds := _classify()
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


## Where the players' camp goes: flat dry ground between `spawn_margin` and `spawn_edge`
## metres in from the map's edge.
func spawn() -> Vector2:
	return _spawn


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
	for k in _side * _side:
		var c := _cell_centre(k)
		wet[k] = 1 if not is_nan(land.water_level(c.x, c.y)) else 0
	var reach := ceili(float(_cfg["wet_distance"]) / _cell)
	var ring := float(_cfg["hilltop_ring"])
	for k in _side * _side:
		var c := _cell_centre(k)
		var kind := "open"
		var grade := land.grade(c.x, c.y)
		if wet[k] == 1:
			kind = "water"
		elif _near(wet, k, reach):
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
			grade += land.grade(c.x, c.y)
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
		var to_edge := minf(minf(c.x - b.position.x, b.end.x - c.x), minf(c.y - b.position.y, b.end.y - c.y))
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

class_name MapOccupancy
extends RefCounted
## What on a generated map is already taken (#429): a fine grid that starts with water,
## settlement footprints and road corridors claimed; each site claims its footprint, or
## fails if any of it is taken. Pure; no autoloads.

## Metres a cell covers.
const CELL := 4.0

var _bounds: Rect2
var _side := 0
var _taken := PackedByteArray()


## `clearance`: metres kept free round roads and settlements beyond their edges.
func _init(map_zones: LandZones, places: Settlements, net: RoadNetwork, clearance: float) -> void:
	_bounds = map_zones.land.bounds()
	_side = ceili(_bounds.size.x / CELL)
	_taken.resize(_side * _side)
	# Water from the zone grid: a fine sample of the water level would cost seconds.
	var zone_cell := map_zones.cell_size()
	for j in map_zones.side():
		for i in map_zones.side():
			var c := map_zones.cell_centre(i, j)
			if str(map_zones.zone_at(c.x, c.y).get("kind", "")) == "water":
				_mark(Rect2(c - Vector2.ONE * zone_cell / 2.0, Vector2.ONE * zone_cell))
	if places != null:
		for place in places.all_places():
			_mark((place["footprint"] as Rect2).grow(clearance))
		for rect in places.reserved():
			_mark(rect.grow(clearance))
	if net != null:
		for road: Dictionary in net.roads():
			var half := float(road["width"]) / 2.0 + clearance
			for p: Vector2 in road["points"]:
				_mark(Rect2(p - Vector2.ONE * half, Vector2.ONE * half * 2.0))


## Whether every cell under `rect` is free.
func is_free(rect: Rect2) -> bool:
	var r := _cells(rect)
	if r.size.x <= 0 or r.size.y <= 0:
		return false
	for j in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			if _taken[j * _side + i] == 1:
				return false
	return true


## Takes `rect` if all of it is free; true when it did.
func claim(rect: Rect2) -> bool:
	if not _bounds.encloses(rect) or not is_free(rect):
		return false
	_mark(rect)
	return true


## Takes `rect`, whatever is there already (room kept round something).
func claim_anyway(rect: Rect2) -> void:
	_mark(rect)


func _mark(rect: Rect2) -> void:
	var r := _cells(rect)
	for j in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			_taken[j * _side + i] = 1


## The cells `rect` touches, clipped to the map.
func _cells(rect: Rect2) -> Rect2i:
	var from := Vector2i(floori((rect.position.x - _bounds.position.x) / CELL), floori((rect.position.y - _bounds.position.y) / CELL))
	var to := Vector2i(ceili((rect.end.x - _bounds.position.x) / CELL), ceili((rect.end.y - _bounds.position.y) / CELL))
	return Rect2i(from, to - from).intersection(Rect2i(0, 0, _side, _side))

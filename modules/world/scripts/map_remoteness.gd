class_name MapRemoteness
extends RefCounted
## How far each place on a generated map is from people (#419, #429), 0 to 1, on the zone
## grid: 0 in a settlement and at the camp, rising with the way there, which counts its
## metres along a road and `off_road` times as much over open land; water cannot be crossed.
## `reach` metres of that way makes 1. Also each cell's distance to the nearest road, which
## site rules read. Pure; no autoloads.

const STEPS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var zones: LandZones

var _reach := 1.0
var _side := 0
var _cell := 1.0
## Per zone cell: the way from people, and metres to the nearest road.
var _way := PackedFloat32Array()
var _to_road := PackedFloat32Array()


func _init(map_zones: LandZones, places: Settlements, net: RoadNetwork, config: Dictionary) -> void:
	zones = map_zones
	_reach = maxf(float(config["reach"]), 1.0)
	_side = zones.side()
	_cell = zones.cell_size()
	var on_road := PackedByteArray()
	on_road.resize(_side * _side)
	if net != null:
		for road: Dictionary in net.roads():
			for p: Vector2 in road["points"]:
				var k := _index(p)
				if k >= 0:
					on_road[k] = 1
	var water := PackedByteArray()
	water.resize(_side * _side)
	for k in _side * _side:
		var c := zones.cell_centre(k % _side, k / _side)
		water[k] = 1 if str(zones.zone_at(c.x, c.y).get("kind", "")) == "water" else 0
	# From people: settlements' footprints and the camp.
	var people: Array[int] = []
	if places != null:
		var all: Array[Dictionary] = places.towns().duplicate()
		if not places.city().is_empty():
			all.append(places.city())
		for place in all:
			var foot: Rect2 = place["footprint"]
			for k in _side * _side:
				if foot.has_point(zones.cell_centre(k % _side, k / _side)):
					people.append(k)
		var camp := _index(places.camp())
		if camp >= 0:
			people.append(camp)
	_way = _spread(people, func(k: int) -> float: return 1.0 if on_road[k] == 1 else float(config["off_road"]), water)
	var roads: Array[int] = []
	for k in _side * _side:
		if on_road[k] == 1:
			roads.append(k)
	_to_road = _spread(roads, func(_k: int) -> float: return 1.0, PackedByteArray())


## 0 near people, 1 at least `reach` metres of way from them.
func at(x: float, z: float) -> float:
	var k := _index(Vector2(x, z))
	return clampf(_way[k] / _reach, 0.0, 1.0) if k >= 0 else 1.0


## Metres from (x, z) to the nearest road (INF without roads).
func road_distance(x: float, z: float) -> float:
	var k := _index(Vector2(x, z))
	return _to_road[k] if k >= 0 else INF


func _index(p: Vector2) -> int:
	var b := zones.land.bounds()
	var i := floori((p.x - b.position.x) / _cell)
	var j := floori((p.y - b.position.y) / _cell)
	if i < 0 or j < 0 or i >= _side or j >= _side:
		return -1
	return j * _side + i


## Cheapest way from any of `sources` to every cell: a step costs its metres times the
## `weight` of the cell it enters; `blocked` cells (1) are never entered.
func _spread(sources: Array[int], weight: Callable, blocked: PackedByteArray) -> PackedFloat32Array:
	var best := PackedFloat32Array()
	best.resize(_side * _side)
	best.fill(INF)
	var done := PackedByteArray()
	done.resize(_side * _side)
	var heap := MinHeap.new()
	for k in sources:
		best[k] = 0.0
		heap.push(0.0, k)
	while not heap.is_empty():
		var k := heap.pop()
		if done[k] == 1:
			continue
		done[k] = 1
		var i := k % _side
		var j := k / _side
		for s in STEPS:
			var ni := i + s.x
			var nj := j + s.y
			if ni < 0 or nj < 0 or ni >= _side or nj >= _side:
				continue
			var n := nj * _side + ni
			if done[n] == 1 or (not blocked.is_empty() and blocked[n] == 1):
				continue
			var cost := best[k] + _cell * (1.4142135 if s.x != 0 and s.y != 0 else 1.0) * float(weight.call(n))
			if cost < best[n]:
				best[n] = cost
				heap.push(cost, n)
	return best

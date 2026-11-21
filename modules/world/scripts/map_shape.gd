class_name MapShape
extends GroundShape
## A generated map (decision 0010, 0012) as the land the voxel terrain and scenery are built
## from: heights shaped by the earthworks, its ponds as water bodies, its roads and tracks
## for keeping scenery off them, and its camp and highway for where play starts. Built once
## per recipe and seed by WorldMaps. Runs without autoloads.

## Metres a pond's water reaches past its survey points: they are a water cell apart.
const POND_REACH := 1.0

## MapRender.build's result: {land, zones, places, net, works, remoteness, sites, low, high}.
var map: Dictionary
var land: WorldLand
var works: Earthworks
## Every site's footprint (see on_site).
var _site_feet: Array[Rect2] = []


func _init(built: Dictionary, water_config: Dictionary) -> void:
	map = built
	var all: MapSites = built.get("sites")
	if all != null:
		for site: Dictionary in all.sites():
			_site_feet.append(site["footprint"])
	land = built["land"]
	works = built["works"]
	water = MapWater.new({"bodies": [], "shore": water_config.get("shore", 4.0), "bank": water_config.get("bank", 8.0)}, height_at)
	(water as MapWater).land = land
	# Each pond's surface over the hull of its survey points, a cell out: wherever the
	# ground stands above the level the terrain hides the surface, so the hull need not
	# follow the shore exactly.
	var cell := float((built["recipe"]["water"] as Dictionary)["cell"]) if built.has("recipe") else 16.0
	var ponds := land.ponds()
	for i in ponds.size():
		var points := land.pond_points(i)
		if points.is_empty():
			continue
		var grown := PackedVector2Array()
		for p in points:
			for d: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				grown.append(p + d * cell * POND_REACH)
		var outline := Geometry2D.convex_hull(grown)
		outline.remove_at(outline.size() - 1)
		var box := Rect2(outline[0], Vector2.ZERO)
		for p in outline:
			box = box.expand(p)
		water.bodies.append({"name": "pond %d" % i, "outline": outline, "level": float(ponds[i]["level"]), "depth": float(ponds[i]["depth"]), "box": box})


func height_at(x: float, z: float) -> float:
	return works.height(x, z) if works != null else land.height(x, z)


func extent() -> Rect2:
	return land.bounds()


func in_water(x: float, z: float) -> bool:
	return not is_nan(land.water_level(x, z))


func near_road(x: float, z: float, margin: float) -> bool:
	return works != null and works.road_distance(x, z) < margin


func on_site(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	for foot in _site_feet:
		if foot.has_point(p):
			return true
	return false


func biomes() -> GroundBiomes:
	return LandBiomes.new(land)


## The lowest and highest ground on the map, metres.
func low() -> float:
	return float(map["low"])


func high() -> float:
	return float(map["high"])


## Where the players' camp is (x, z), and the ground there.
func camp() -> Vector3:
	var places: Settlements = map["places"]
	var c := places.camp() if places != null else Vector2.ZERO
	return Vector3(c.x, height_at(c.x, c.y), c.y)


## The city as the map places it (#472): {centre (on its level), size (metres a side), toward
## (unit, on the ground plane: the side the highway arrives at)}; empty without a city.
func city() -> Dictionary:
	var places: Settlements = map["places"]
	if places == null or places.city().is_empty():
		return {}
	var c: Dictionary = places.city()
	var foot: Rect2 = c["footprint"]
	var centre := Vector3(foot.get_center().x, float(c["level"]), foot.get_center().y)
	# The connector nearest the highway's end: that is the side the road comes in at.
	var toward := Vector3.FORWARD
	var points := highway()
	if not points.is_empty():
		var end := points[points.size() - 1]
		var best := INF
		for k: Vector3 in c["connectors"]:
			var d := Vector2(k.x, k.z).distance_to(end)
			if d < best:
				best = d
				toward = Vector3(k.x - centre.x, 0.0, k.z - centre.z).normalized()
	return {"centre": centre, "size": foot.size.x, "toward": toward}


## The centres of every site of `kind` (a key of the recipe's `sites.kinds`), on the
## ground there: the earthworks level each site's pad, so this is the pad's height.
func sites(kind: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var all: MapSites = map.get("sites")
	if all == null:
		return out
	for s: Dictionary in all.sites():
		if s["kind"] == kind:
			var c: Vector2 = s["centre"]
			out.append(Vector3(c.x, height_at(c.x, c.y), c.y))
	return out


## The highway from the camp: its points from the camp's end.
func highway() -> PackedVector2Array:
	var net: RoadNetwork = map["net"]
	if net == null:
		return PackedVector2Array()
	for road: Dictionary in net.roads():
		if road["kind"] == "highway":
			return road["points"]
	return PackedVector2Array()


## `metres` along the highway from the camp, on the ground (the end of it past its length).
func road_point(metres: float) -> Vector3:
	var points := highway()
	if points.is_empty():
		var c := camp()
		return Vector3(c.x, c.y, c.z - metres)
	var left := maxf(metres, 0.0)
	for k in range(1, points.size()):
		var step := points[k].distance_to(points[k - 1])
		if left <= step:
			var p := points[k - 1].lerp(points[k], left / maxf(step, 0.001))
			return Vector3(p.x, height_at(p.x, p.y), p.y)
		left -= step
	var end := points[points.size() - 1]
	return Vector3(end.x, height_at(end.x, end.y), end.y)


## Which way the highway leaves the camp, on the ground plane.
func forward() -> Vector3:
	var points := highway()
	if points.size() < 2:
		return Vector3.FORWARD
	var reach := mini(points.size() - 1, 8)
	var d := points[reach] - points[0]
	return Vector3(d.x, 0.0, d.y).normalized() if d.length() > 0.01 else Vector3.FORWARD

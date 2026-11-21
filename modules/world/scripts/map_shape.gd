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
## Each footprint's site kind, in the same order.
var _site_kinds: Array[String] = []


func _init(built: Dictionary, water_config: Dictionary) -> void:
	map = built
	var all: MapSites = built.get("sites")
	if all != null:
		for site: Dictionary in all.sites():
			_site_feet.append(site["footprint"])
			_site_kinds.append(str(site["kind"]))
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


func road_edge_distance(x: float, z: float) -> float:
	return maxf(works.road_distance(x, z), 0.0) if works != null else INF


func on_site(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	for foot in _site_feet:
		if foot.has_point(p):
			return true
	return false


## Whether (x, z) is on a site's pad or within `clearance` of it: metres by site kind, with a
## `default` for kinds not listed.
func near_site(x: float, z: float, clearance: Dictionary) -> bool:
	var p := Vector2(x, z)
	var fallback := float(clearance.get("default", 0.0))
	for i in _site_feet.size():
		if _site_feet[i].grow(float(clearance.get(_site_kinds[i], fallback))).has_point(p):
			return true
	return false


## Whether a circle of `radius` at (x, z) reaches onto a site's pad: ground what stands there
## (a farm, a mast) already holds.
func site_within(x: float, z: float, radius: float) -> bool:
	var p := Vector2(x, z)
	for foot in _site_feet:
		if foot.grow(radius).has_point(p):
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


## Every site, in the order the map placed them: {kind, centre (on the pad's level),
## footprint (Rect2 on x, z), connectors (Vector3, the middle of each side), toward (unit, on
## the ground plane: from the centre to the side its track leaves by, or to the side nearest
## a road when it has no track), remoteness (0 to 1, see MapRemoteness), track (where its
## track meets the road network, see `_track_mouth`; empty when it has none)}.
func site_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var all: MapSites = map.get("sites")
	if all == null:
		return out
	# A site's track is named after its kind and its place in the list (MapRender.build).
	var starts: Dictionary[String, Vector2] = {}
	var tracks: Dictionary[String, Dictionary] = {}
	var net: RoadNetwork = map.get("net")
	if net != null:
		for road: Dictionary in net.roads():
			var points: PackedVector2Array = road["points"]
			if road["kind"] == "track" and not points.is_empty():
				starts[str(road["from"])] = points[0]
				tracks[str(road["from"])] = road
	var sites := all.sites()
	for i in sites.size():
		var s: Dictionary = sites[i]
		var c: Vector2 = s["centre"]
		var centre := Vector3(c.x, height_at(c.x, c.y), c.y)
		var name := "%s %d" % [s["kind"], i]
		var best := INF
		var toward := Vector3.FORWARD
		for k: Vector3 in s["connectors"]:
			var d := Vector2(k.x, k.z).distance_to(starts[name]) if starts.has(name) else road_edge_distance(k.x, k.z)
			if d < best:
				best = d
				toward = Vector3(k.x - c.x, 0.0, k.z - c.y).normalized()
		var mouth := _track_mouth(tracks[name], net) if tracks.has(name) else {}
		out.append({"kind": s["kind"], "centre": centre, "footprint": s["footprint"], "connectors": s["connectors"], "toward": toward,
			"remoteness": float(s.get("remoteness", 0.0)), "track": mouth})
	return out


## The site's own track and where it meets the road network (a road, or a track built before
## it): {points (x, z, from the site's end to the road's), track_width, end (on the ground
## there), up (unit, on the ground plane: the way the track leaves the road), along (unit: the
## way the road it meets runs there), width (that road's width), length (the track's metres)}.
func _track_mouth(track: Dictionary, net: RoadNetwork) -> Dictionary:
	var points: PackedVector2Array = track["points"]
	var end := points[points.size() - 1]
	# A few samples back, so the track's last square turn onto the road does not decide it.
	var back := points[maxi(points.size() - 4, 0)]
	var up := Vector3(back.x - end.x, 0.0, back.y - end.y)
	var along := Vector3(up.z, 0.0, -up.x)
	var width := 0.0
	var best := INF
	# Only roads made before it: a track joins those, and later tracks may join it near its end.
	for road: Dictionary in net.roads():
		if is_same(road, track):
			break
		var line: PackedVector2Array = road["points"]
		for k in line.size():
			var d := line[k].distance_squared_to(end)
			if d < best and line.size() > 1:
				best = d
				var a := line[maxi(k - 1, 0)]
				var b := line[mini(k + 1, line.size() - 1)]
				along = Vector3(b.x - a.x, 0.0, b.y - a.y)
				width = float(road["width"])
	return {"points": points, "track_width": float(track["width"]), "end": Vector3(end.x, height_at(end.x, end.y), end.y), "up": up.normalized() if up.length() > 0.01 else Vector3.FORWARD,
		"along": along.normalized() if along.length() > 0.01 else Vector3.RIGHT, "width": width, "length": MapRender.track_length(track)}


## The map's power lines (#494), each {kind ("high_voltage" or "low_voltage"), from
## ("substation", a settlement, or "line N": a tap off line N of this list), to, points (each
## tower's foot, on the ground there, from the line's source out; a high-voltage line's first
## is its terminal in the substation yard, on the yard's level), sag (the wires' dip as a
## share of a span's length). Empty on a map without them.
func power_lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var power: MapPower = map.get("power")
	if power == null:
		return out
	for line: Dictionary in power.lines():
		var feet: Array[Vector3] = []
		var station := power.substation()
		for p: Vector2 in line["points"]:
			var on_yard := not station.is_empty() and (station["yard"] as Rect2).has_point(p)
			feet.append(Vector3(p.x, float(station["level"]) if on_yard else height_at(p.x, p.y), p.y))
		out.append({"kind": line["kind"], "from": line["from"], "to": line["to"], "points": feet, "sag": line["sag"]})
	return out


## The substation the high-voltage lines start from: {centre (on its pad's level), size
## (metres a side), base (the lowest ground under it)}; empty without one.
func power_substation() -> Dictionary:
	var power: MapPower = map.get("power")
	if power == null or power.substation().is_empty():
		return {}
	var station := power.substation()
	var c: Vector2 = station["centre"]
	return {"centre": Vector3(c.x, float(station["level"]), c.y), "size": (station["yard"] as Rect2).size.x, "base": float(station["base"])}


## Whether a circle of `radius` at (x, z) reaches a power tower's feet or the substation yard.
func power_within(x: float, z: float, radius: float) -> bool:
	var power: MapPower = map.get("power")
	return power != null and power.tower_within(Vector2(x, z), radius)


## The map's power lines are map data like its roads, there whether or not the power module
## that puts up their towers is on, so their corridors are kept clear either way: the world
## cannot ask which modules are loaded without depending on them.
func near_power(x: float, z: float, high_voltage: float, low_voltage: float) -> bool:
	var power: MapPower = map.get("power")
	return power != null and power.near(x, z, high_voltage, low_voltage)


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

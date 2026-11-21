class_name MapSites
extends RefCounted
## Sites and props placed on a generated map by zone and remoteness (#429, decision 0010):
## farms on flat land near a road, the lone cabin deep in the woods, antennas and lookouts on
## hilltops, water towers by farms and towns. Each kind has its rules in the recipe's
## `sites.kinds`, tried in the order given (so a kind may stand near one placed before it);
## every footprint is claimed on one occupancy map, so nothing overlaps a road, a settlement,
## water or another site. Pure and seeded; no autoloads.

## Fields each kind needs (numbers, [low, high] pairs and lists of zone kinds).
const KIND := {"count": "a", "zones": "a", "remoteness": "a", "road": "a", "spacing": "n", "size": "a", "max_grade": "n"}
## Fields the `sites` section needs besides its kinds.
const SECTION := {"clearance": "n", "settlement_clearance": "n", "edge_margin": "n", "spacing_any": "n", "kinds": "d"}

## How much longer than the straight way to the nearest road a track usually runs (the
## median over the shipped recipes' first eight seeds is about 1.2).
const TRACK_WINDING := 1.25

var remoteness: MapRemoteness

## Each {kind, centre (x, z), footprint (Rect2), level, remoteness}.
var _sites: Array[Dictionary] = []
## Kinds asked for and how many were placed: {kind: [placed, wanted at least]}.
var _counts: Dictionary[String, Vector2i] = {}
var _spacing_any := 0.0
var _low := 0.0
var _high := 0.0


func _init(map_zones: LandZones, places: Settlements, net: RoadNetwork, far: MapRemoteness, config: Dictionary, seed_value: int) -> void:
	remoteness = far
	var occupancy := MapOccupancy.new(map_zones, places, net, float(config["clearance"]))
	# Settlements keep more room round them than roads do: farms crowding the city read as
	# its suburbs, not countryside.
	if places != null:
		var all: Array[Dictionary] = places.towns().duplicate()
		if not places.city().is_empty():
			all.append(places.city())
		for place in all:
			occupancy.claim_anyway((place["footprint"] as Rect2).grow(float(config["settlement_clearance"])))
	var inside := map_zones.land.bounds().grow(-float(config["edge_margin"]))
	_spacing_any = float(config["spacing_any"])
	# The land's height range over the zone grid, for kinds that stand only on high ground.
	_low = INF
	_high = -INF
	for j in map_zones.side():
		for i in map_zones.side():
			var c := map_zones.cell_centre(i, j)
			var h := map_zones.land.height(c.x, c.y)
			_low = minf(_low, h)
			_high = maxf(_high, h)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "sites"])
	# Candidate spots: the zone cells' middles, shuffled once per kind.
	var spots: Array[Vector2] = []
	for j in map_zones.side():
		for i in map_zones.side():
			spots.append(map_zones.cell_centre(i, j))
	var towns: Array[Rect2] = []
	if places != null:
		for t: Dictionary in places.towns():
			towns.append(t["footprint"])
		if not places.city().is_empty():
			towns.append(places.city()["footprint"])
	var kinds: Dictionary = config["kinds"]
	for kind: String in kinds:
		var rule: Dictionary = kinds[kind]
		var count: Array = rule["count"]
		var wanted := rng.randi_range(int(count[0]), int(count[1]))
		var placed := 0
		_shuffle(spots, rng)
		var order := spots
		# High kinds (antennas, lookouts) try the highest spots first: a hilltop zone is only
		# higher than its ring, and can lie low.
		if bool(rule.get("prefer_high", false)):
			order = spots.duplicate()
			var land := map_zones.land
			var heights: Dictionary[Vector2, float] = {}
			for spot in order:
				heights[spot] = land.height(spot.x, spot.y)
			order.sort_custom(func(a: Vector2, b: Vector2) -> bool: return heights[a] > heights[b])
		for spot in order:
			if not inside.has_point(spot):
				continue
			if placed >= wanted:
				break
			if _fits(spot, kind, rule, map_zones, towns) and _claim(spot, kind, rule, occupancy, map_zones.land):
				placed += 1
		_counts[kind] = Vector2i(placed, int(count[0]))


func sites() -> Array[Dictionary]:
	return _sites


## Per kind: how many were placed, and the least the recipe asked for.
func counts() -> Dictionary[String, Vector2i]:
	return _counts


func _fits(spot: Vector2, kind: String, rule: Dictionary, map_zones: LandZones, towns: Array[Rect2]) -> bool:
	if not (rule["zones"] as Array).has(str(map_zones.zone_at(spot.x, spot.y).get("kind", ""))):
		return false
	var far := remoteness.at(spot.x, spot.y)
	var band: Array = rule["remoteness"]
	if far < float(band[0]) or far > float(band[1]):
		return false
	var road := remoteness.road_distance(spot.x, spot.y)
	var reach: Array = rule["road"]
	if road < float(reach[0]) or road > float(reach[1]):
		return false
	# A spot whose track would likely run longer than its kind allows is passed over, so a
	# spot nearer a road is tried instead of the site being dropped once its track is laid.
	if rule.has("max_track") and road * TRACK_WINDING > float(rule["max_track"]):
		return false
	if map_zones.land.grade(spot.x, spot.y) > float(rule["max_grade"]):
		return false
	if rule.has("min_height") and map_zones.land.height(spot.x, spot.y) < lerpf(_low, _high, float(rule["min_height"])):
		return false
	var spacing := float(rule["spacing"])
	var size: Array = rule["size"]
	var half := Vector2(float(size[0]), float(size[1])) / 2.0
	for s in _sites:
		if s["kind"] == kind and (s["centre"] as Vector2).distance_to(spot) < spacing:
			return false
		# Any two sites keep a gap, so an antenna never stands against a lookout.
		if (s["footprint"] as Rect2).grow(_spacing_any).intersects(Rect2(spot - half, half * 2.0)):
			return false
	# Near another kind (a water tower by a farm) or near a town or the city.
	if rule.has("near"):
		var near := str(rule["near"])
		var within := float(rule.get("near_distance", 80.0))
		var close := false
		if near == "town":
			# From the town's edge: the city is hundreds of metres across.
			close = towns.any(func(t: Rect2) -> bool: return MapSites.outside(t, spot) <= within)
		else:
			close = _sites.any(func(s: Dictionary) -> bool: return s["kind"] == near and (s["centre"] as Vector2).distance_to(spot) <= within)
		if not close:
			return false
	return true


func _claim(spot: Vector2, kind: String, rule: Dictionary, occupancy: MapOccupancy, land: WorldLand) -> bool:
	var size: Array = rule["size"]
	var foot := Rect2(spot - Vector2(float(size[0]), float(size[1])) / 2.0, Vector2(float(size[0]), float(size[1])))
	if not occupancy.claim(foot):
		return false
	var level := land.height(spot.x, spot.y)
	# Where a track may leave it: the middle of each side.
	var connectors: Array[Vector3] = [
		Vector3(spot.x, level, foot.position.y), Vector3(spot.x, level, foot.end.y),
		Vector3(foot.position.x, level, spot.y), Vector3(foot.end.x, level, spot.y),
	]
	_sites.append({"kind": kind, "centre": spot, "footprint": foot, "level": level, "remoteness": remoteness.at(spot.x, spot.y), "connectors": connectors})
	return true


## Drops the sites at `indices` (their tracks were too long, see MapRender.build), keeping
## the rest in order.
func drop(indices: Array[int]) -> void:
	for i in range(indices.size() - 1, -1, -1):
		var kind := str(_sites[indices[i]]["kind"])
		_counts[kind] = _counts[kind] - Vector2i(1, 0)
		_sites.remove_at(indices[i])


## Whether the straight line from `a` to `b` passes through `rect` (sampled every metre).
static func segment_hits(rect: Rect2, a: Vector2, b: Vector2) -> bool:
	var steps := maxi(ceili(a.distance_to(b)), 1)
	for k in steps + 1:
		if rect.has_point(a.lerp(b, float(k) / steps)):
			return true
	return false


## How far `p` lies outside `rect` (0 inside).
static func outside(rect: Rect2, p: Vector2) -> float:
	return Vector2(maxf(maxf(rect.position.x - p.x, p.x - rect.end.x), 0.0), maxf(maxf(rect.position.y - p.y, p.y - rect.end.y), 0.0)).length()


static func _shuffle(spots: Array[Vector2], rng: RandomNumberGenerator) -> void:
	for i in range(spots.size() - 1, 0, -1):
		var k := rng.randi_range(0, i)
		var t := spots[i]
		spots[i] = spots[k]
		spots[k] = t

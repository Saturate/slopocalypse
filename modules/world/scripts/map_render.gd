class_name MapRender
extends RefCounted
## A map recipe's world drawn top-down (#427, #428, #448): hill shading over colour by
## height, biomes and water, then the layers asked for (zones, settlements, roads,
## earthworks), and a summary with a coarse height and zone grid for a hover readout. Used by
## the preview tool, the local map viewer and the server's admin app. Pure: safe to run on a
## worker thread (it builds its own land and touches no nodes). No autoloads.

const LIGHT := Vector3(-0.6, 0.7, -0.4)
const LOW := Color(0.36, 0.52, 0.27)
const HIGH := Color(0.62, 0.55, 0.42)
const FOREST := Color(0.16, 0.33, 0.15)
const ROCK := Color(0.55, 0.54, 0.5)
const DRY := Color(0.72, 0.66, 0.38)
const SAND := Color(0.86, 0.8, 0.6)
## The sea, shallow to deep: bluer and darker than a pond.
const SEA_SHALLOW := Color(0.3, 0.6, 0.68)
const SEA_DEEP := Color(0.08, 0.2, 0.38)
## Metres of sea from the shallow tint to the deep one.
const SEA_DEEP_AT := 12.0
## The harbour spot: a jetty drawn from the shore out to sea.
const HARBOUR := Color(0.55, 0.35, 0.15)
const SHALLOW := Color(0.36, 0.6, 0.7)
const DEEP := Color(0.12, 0.27, 0.42)
## Metres of water from the shallow tint to the deep one.
const DEEP_AT := 3.0
const ZONE_EDGE := Color(0.1, 0.1, 0.1)
const CITY := Color(0.85, 0.15, 0.1)
const SPAWN := Color(1, 1, 1)
const TOWN := Color(0.95, 0.55, 0.1)
const ROAD := Color(0.18, 0.18, 0.2)
const TRACK := Color(0.45, 0.36, 0.25)
const TUNNEL := Color(0.62, 0.3, 0.75)
const BRIDGE := Color(0.55, 0.85, 1.0)
## Power lines: high-voltage in bright yellow with a dark dot per pylon, pole lines in pink.
const HIGH_VOLTAGE := Color(1.0, 0.9, 0.15)
const POLE_LINE := Color(0.95, 0.45, 0.85)
const TOWER := Color(0.1, 0.1, 0.1)
const ALL_LAYERS := "zones,settlements,roads,earthworks,sites,power"
## Each site kind's colour on the map; kinds not listed are drawn white.
const SITE_COLOURS := {"farm": Color(0.55, 0.36, 0.18), "water_tower": Color(0.95, 0.85, 0.2), "town_tower": Color(0.95, 0.85, 0.2),
	"antenna": Color(0.85, 0.85, 0.9), "lookout": Color(0.75, 0.45, 0.85), "cabin": Color(0.6, 0.12, 0.12)}
## The remoteness tint: near people to far out, laid over the land at this strength.
const NEAR := Color(0.2, 0.45, 1.0)
const FAR := Color(1.0, 0.25, 0.15)
const TINT := 0.45
## Cells a side of the stats grid the viewer reads heights and zones from on hover.
const GRID_CELLS := 128


## Fields a recipe needs, section by section (a section left out is skipped: the stages
## after it don't run). "n" is a number, "d" an object of further fields, "a" a list, "s" text.
const RECIPE := {"size": "n", "relief": "n", "hill_mask": {"frequency": "n", "from": "n", "to": "n"}, "layers": "a"}
const LAYER := {"frequency": "n", "amplitude": "n"}
const SECTIONS := {
	"coast": {"sea_level": "n", "edge": "n", "radius": "n", "roundness": "n", "noise": {"frequency": "n", "amplitude": "n", "octaves": "n"}, "sea_depth": "n",
		"inland": "n", "beach": {"rise": "n", "sea_band": "n", "land_band": "n", "sand_grade": "n", "sand_height": "n"},
		"cliff": {"rise": "n", "sea_band": "n", "land_band": "n", "inland": "n", "from": "n", "to": "n"},
		"islets": {"frequency": "n", "threshold": "n", "near": "n", "far": "n", "rise": "n"}},
	"water": {"cell": "n", "deepen": "n", "min_depth": "n", "min_area": "n", "max_area": "n", "freeboard": "n"},
	"biomes": {"forest_frequency": "n", "forest_threshold": "n", "dry_frequency": "n", "rock_frequency": "n", "rock_threshold": "n",
		"map_metres_per_texel": "n", "rock_grade_from": "n", "rock_grade_to": "n", "hill_forest": "n", "lowland_forest": "n",
		"woodland_frequency": "n", "rock_patch_frequency": "n"},
	"zones": {"cell": "n", "slope_grade": "n", "flat_grade": "n", "forest_cutoff": "n", "wet_distance": "n", "hilltop_rise": "n",
		"hilltop_ring": "n", "spawn_margin": "n", "spawn_edge": "n", "uses": "d"},
	"settlements": {"city": {"use": "s", "size": "n"}, "town": {"use": "s", "size": "n", "spacing": "n", "max": "n"},
		"camp": {"clearance": "n", "size": "n"}, "edge_margin": "n"},
	"roads": {"kinds": "d", "cost": {"forest": "n", "slope": "n", "wetland": "n", "hilltop": "n", "over_grade": "n"},
		"sample": "n", "profile_window": "n"},
	"earthworks": {"bank_grade": "n", "shoulder": "n", "reach": "n"},
	"remoteness": {"reach": "n", "off_road": "n"},
	"sites": MapSites.SECTION,
	"power": MapPower.SECTION,
}
const ROAD_KIND := {"width": "n", "max_grade": "n", "min_radius": "n", "max_cut": "n", "max_fill": "n"}
## Kinds the road network builds; an edited recipe must still have them.
const ROAD_KINDS: Array[String] = ["highway", "two_lane"]
## Ranges for the fields that set how much work a build is: a cell or step near 0, or a huge
## map, scan or count, would keep a render (and the server's worker) busy for minutes or for
## good (a road sample of 0 never ends). Wide enough for any recipe worth looking at.
const LIMITS := {
	"size": Vector2(256, 4096),
	"coast.roundness": Vector2(1, 16),
	"coast.noise.octaves": Vector2(1, 8),
	"coast.sea_depth": Vector2(1, 200),
	"coast.edge": Vector2(0, 1000),
	"coast.inland": Vector2(1, 3000),
	"coast.cliff.inland": Vector2(1, 3000),
	"coast.noise.amplitude": Vector2(0, 1000),
	"settlements.harbour.reach": Vector2(16, 600),
	"settlements.harbour.size": Vector2(4, 100),
	"water.cell": Vector2(4, 64),
	"zones.cell": Vector2(4, 64),
	"zones.wet_distance": Vector2(0, 200),
	"zones.hilltop_ring": Vector2(0, 400),
	"biomes.map_metres_per_texel": Vector2(1, 32),
	"settlements.town.max": Vector2(0, 16),
	# At least the camp's fence (world.json camp.fence, 12 m from the middle) and a metre
	# round it; WorldRoot also says so when the two disagree.
	"settlements.camp.size": Vector2(28, 96),
	"roads.sample": Vector2(1, 32),
	"roads.profile_window": Vector2(0, 500),
	"earthworks.bank_grade": Vector2(0.1, 3),
	"earthworks.shoulder": Vector2(0, 20),
	"earthworks.reach": Vector2(0, 200),
	"remoteness.reach": Vector2(100, 20000),
	"remoteness.off_road": Vector2(1, 20),
	"sites.clearance": Vector2(0, 50),
	"sites.settlement_clearance": Vector2(0, 300),
	"sites.edge_margin": Vector2(0, 500),
	"power.edge_margin": Vector2(0, 500),
	"power.high_voltage.towns": Vector2(0, 16),
	"power.high_voltage.foot": Vector2(0, 20),
	"power.high_voltage.max_turn": Vector2(0, 90),
	"power.high_voltage.yard": Vector2(20, 48),
	"power.poles.branch_angle": Vector2(0, 90),
	"power.poles.count": Vector2(0, 32),
	"power.poles.max_length": Vector2(0, 5000),
}
## Ranges a power line's [shortest, longest] span must keep to, metres: a short span makes a
## route search try thousands of spots, and wires refuse spans past their max_span (400 m).
const POWER_SPANS := {"high_voltage": Vector2(50, 400), "poles": Vector2(10, 100)}
## Most site kinds, and most of one kind, a recipe may ask for.
const MAX_SITE_KINDS := 24
const MAX_SITES := 64
const MAX_LAYERS := 8
const MAX_OCTAVES := 8
const MAX_ROAD_RADIUS := 500.0
## A road kind's cross-slope cost past this would route a track the long way round every hill.
const MAX_CROSS_SLOPE := 50.0


## What is wrong with `recipe` for building a map, or "" when nothing is: checked before any
## work, so a broken edit is an answer, never a script error halfway through.
static func check(recipe: Dictionary) -> String:
	var problem := _check_fields(recipe, RECIPE, "")
	if not problem.is_empty():
		return problem
	var layers: Array = recipe["layers"]
	if layers.is_empty() or layers.size() > MAX_LAYERS:
		return "layers: 1 to %d" % MAX_LAYERS
	for i in layers.size():
		var layer: Variant = layers[i]
		if not layer is Dictionary:
			return "layers[%d]: not an object" % i
		problem = _check_fields(layer, LAYER, "layers[%d]." % i)
		if not problem.is_empty():
			return problem
		var octaves: Variant = (layer as Dictionary).get("octaves", 1)
		if not (octaves is float or octaves is int) or float(octaves) < 1.0 or float(octaves) > MAX_OCTAVES:
			return "layers[%d].octaves: 1 to %d" % [i, MAX_OCTAVES]
	problem = _check_island(recipe)
	if not problem.is_empty():
		return problem
	for section: String in SECTIONS:
		if recipe.has(section):
			if not recipe[section] is Dictionary:
				return "%s: not an object" % section
			problem = _check_fields(recipe[section], SECTIONS[section], section + ".")
			if not problem.is_empty():
				return problem
	if recipe.has("roads"):
		for kind in ROAD_KINDS:
			var spec: Variant = (recipe["roads"]["kinds"] as Dictionary).get(kind)
			if not spec is Dictionary:
				return "roads.kinds.%s: missing" % kind
			problem = _check_fields(spec, ROAD_KIND, "roads.kinds.%s." % kind)
			if not problem.is_empty():
				return problem
			var radius := float((spec as Dictionary)["min_radius"])
			if radius < 0.0 or radius > MAX_ROAD_RADIUS:
				return "roads.kinds.%s.min_radius: 0 to %d" % [kind, MAX_ROAD_RADIUS]
		for kind: String in recipe["roads"]["kinds"]:
			var spec: Variant = recipe["roads"]["kinds"][kind]
			if spec is Dictionary and (spec as Dictionary).has("cross_slope"):
				var cross: Variant = spec["cross_slope"]
				if not (cross is float or cross is int) or float(cross) < 0.0 or float(cross) > MAX_CROSS_SLOPE:
					return "roads.kinds.%s.cross_slope: a number, 0 to %d" % [kind, MAX_CROSS_SLOPE]
	if recipe.has("sites"):
		var kinds: Dictionary = recipe["sites"]["kinds"]
		if kinds.size() > MAX_SITE_KINDS:
			return "sites.kinds: at most %d" % MAX_SITE_KINDS
		for kind: String in kinds:
			if not kinds[kind] is Dictionary:
				return "sites.kinds.%s: not an object" % kind
			problem = _check_fields(kinds[kind], MapSites.KIND, "sites.kinds.%s." % kind)
			if not problem.is_empty():
				return problem
			var count: Array = kinds[kind]["count"]
			if count.size() != 2 or not (count[1] is float or count[1] is int) or float(count[1]) > MAX_SITES:
				return "sites.kinds.%s.count: [least, most], most at most %d" % [kind, MAX_SITES]
			var rule: Dictionary = kinds[kind]
			if rule.has("max_track") and not ((rule["max_track"] is float or rule["max_track"] is int) and float(rule["max_track"]) > 0.0):
				return "sites.kinds.%s.max_track: metres, more than 0" % kind
	if recipe.has("power"):
		for kind: String in POWER_SPANS:
			var span: Array = recipe["power"][kind]["span"]
			var limit: Vector2 = POWER_SPANS[kind]
			if span.size() != 2 or not (span[0] is float or span[0] is int) or not (span[1] is float or span[1] is int) \
					or float(span[0]) < limit.x or float(span[1]) > limit.y or float(span[0]) > float(span[1]):
				return "power.%s.span: [shortest, longest], %d to %d" % [kind, limit.x, limit.y]
		var reach: Array = recipe["power"]["high_voltage"]["substation"]
		if reach.size() != 2 or not (reach[0] is float or reach[0] is int) or not (reach[1] is float or reach[1] is int) \
				or float(reach[0]) < 0.0 or float(reach[1]) > 500.0 or float(reach[0]) > float(reach[1]):
			return "power.high_voltage.substation: [nearest, furthest], 0 to 500"
	for path: String in LIMITS:
		var value: Variant = _at(recipe, path)
		var limit: Vector2 = LIMITS[path]
		if value != null and (float(value) < limit.x or float(value) > limit.y):
			return "%s: %d to %d" % [path, limit.x, limit.y]
	return ""


## What is wrong with the island's parts of `recipe` (#454): the islets' ring, the camp's
## distance to the sea and the harbour's jetty lengths, or "".
static func _check_island(recipe: Dictionary) -> String:
	var coast: Variant = recipe.get("coast")
	if coast is Dictionary and (coast as Dictionary).get("islets") is Dictionary:
		var islets: Dictionary = coast["islets"]
		if (islets.get("near") is float or islets.get("near") is int) and (islets.get("far") is float or islets.get("far") is int) and float(islets["near"]) > float(islets["far"]):
			return "coast.islets: near no further out than far"
	var places: Variant = recipe.get("settlements")
	if not places is Dictionary:
		return ""
	var camp: Variant = (places as Dictionary).get("camp")
	if camp is Dictionary and (camp as Dictionary).has("sea") and not _is_range((camp as Dictionary)["sea"], 0.0, 2000.0):
		return "settlements.camp.sea: [nearest, furthest], 0 to 2000"
	var harbour: Variant = (places as Dictionary).get("harbour")
	if harbour == null:
		return ""
	if not harbour is Dictionary:
		return "settlements.harbour: not an object"
	var problem := _check_fields(harbour, {"reach": "n", "min_depth": "n", "max_grade": "n", "size": "n"}, "settlements.harbour.")
	if not problem.is_empty():
		return problem
	if not _is_range((harbour as Dictionary).get("length"), 1.0, 200.0):
		return "settlements.harbour.length: [shortest, longest], 1 to 200"
	return ""


## Whether `value` is [low, high] numbers within `from` to `to`, low no more than high.
static func _is_range(value: Variant, from: float, to: float) -> bool:
	if not value is Array or (value as Array).size() != 2:
		return false
	var pair: Array = value
	if not (pair[0] is float or pair[0] is int) or not (pair[1] is float or pair[1] is int):
		return false
	return float(pair[0]) >= from and float(pair[1]) <= to and float(pair[0]) <= float(pair[1])


## The number at a dotted path, or null where its section is left out (fields are checked
## before this, so whatever is there is a number).
static func _at(data: Dictionary, path: String) -> Variant:
	var here: Variant = data
	for part in path.split("."):
		if not here is Dictionary or not (here as Dictionary).has(part):
			return null
		here = here[part]
	return here


static func _check_fields(data: Dictionary, wanted: Dictionary, at: String) -> String:
	for key: String in wanted:
		if not data.has(key):
			return "%s%s: missing" % [at, key]
		var kind: Variant = wanted[key]
		var value: Variant = data[key]
		if kind is Dictionary:
			if not value is Dictionary:
				return "%s%s: not an object" % [at, key]
			var inner := _check_fields(value, kind, "%s%s." % [at, key])
			if not inner.is_empty():
				return inner
		elif kind == "n" and not (value is float or value is int):
			return "%s%s: not a number" % [at, key]
		elif kind == "d" and not value is Dictionary:
			return "%s%s: not an object" % [at, key]
		elif kind == "a" and not value is Array:
			return "%s%s: not a list" % [at, key]
		elif kind == "s" and not value is String:
			return "%s%s: not text" % [at, key]
	return ""


## Everything for one view: {image (Image), stats (Dictionary)}. `layers` names what to draw
## over the land (ALL_LAYERS when empty); `region` the square of the map to draw (all of it
## when empty).
static func make(recipe: Dictionary, seed_value: int, pixels: int, layers: PackedStringArray, region := Rect2()) -> Dictionary:
	var world := build(recipe, seed_value)
	return {"image": draw(world, pixels, layers, region), "stats": world_stats(world, layers)}


## The map's stages built once: {land, zones, places, net, works (each null when its recipe
## section is left out), built_ms, low, high (the land's height range, so a close-up is
## coloured like the whole map)}. Drawing it again, or a part of it, needs no rebuild.
static func build(recipe: Dictionary, seed_value: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var land := WorldLand.new(recipe, seed_value)
	var zones: LandZones = null
	var places: Settlements = null
	var net: RoadNetwork = null
	var zones_cfg: Variant = recipe.get("zones")
	if zones_cfg is Dictionary:
		zones = LandZones.new(land, zones_cfg)
		var places_cfg: Variant = recipe.get("settlements")
		if places_cfg is Dictionary:
			places = Settlements.new(zones, places_cfg)
			var roads_cfg: Variant = recipe.get("roads")
			if roads_cfg is Dictionary:
				net = RoadNetwork.new(places, roads_cfg)
	var far: MapRemoteness = null
	var far_cfg: Variant = recipe.get("remoteness")
	if far_cfg is Dictionary and zones != null:
		far = MapRemoteness.new(zones, places, net, far_cfg)
	var sites: MapSites = null
	var sites_cfg: Variant = recipe.get("sites")
	if sites_cfg is Dictionary and far != null:
		sites = MapSites.new(zones, places, net, far, sites_cfg, seed_value)
		# Each site's track to the nearest road, around the other sites.
		if net != null:
			var feet: Array[Rect2] = []
			for site in sites.sites():
				feet.append(site["footprint"])
			var kinds: Dictionary = sites_cfg["kinds"]
			var dropped: Array[int] = []
			for i in sites.sites().size():
				var others := feet.duplicate()
				others.remove_at(i)
				var site: Dictionary = sites.sites()[i]
				var name := "%s %d" % [site["kind"], i]
				var rule: Dictionary = kinds[site["kind"]]
				# A site placed by another (a water tower by its farm) goes when that one has.
				if rule.has("near") and str(rule["near"]) != "town" and not _near_kept(sites.sites(), dropped, i, str(rule["near"]), float(rule.get("near_distance", 80.0))):
					dropped.append(i)
					continue
				net.add_track(site, name, others)
				# A site whose track winds further than its kind allows is dropped with it,
				# before any later track can join it.
				var limit := float(rule.get("max_track", INF))
				var roads := net.roads()
				if not roads.is_empty() and roads.back()["from"] == name and track_length(roads.back()) > limit:
					roads.pop_back()
					dropped.append(i)
			if not dropped.is_empty():
				_renumber_tracks(net, sites, dropped)
	# Earthworks last: they shape the land under every road, track, settlement and site.
	var works: Earthworks = null
	var works_cfg: Variant = recipe.get("earthworks")
	if works_cfg is Dictionary and places != null:
		works = Earthworks.new(land, places, net, works_cfg, sites)
	# Power lines after everything that shapes the land: they keep off it all.
	var power: MapPower = null
	var power_cfg: Variant = recipe.get("power")
	var power_ms := 0.0
	if power_cfg is Dictionary and works != null:
		# Timed here, not with Prof: the map is built on a worker thread, and Prof's zones
		# are only for the main one.
		var power_started := Time.get_ticks_usec()
		power = MapPower.new(works, places, net, sites, power_cfg, seed_value)
		power_ms = float(Time.get_ticks_usec() - power_started) / 1000.0
	var world := {"land": land, "zones": zones, "places": places, "net": net, "works": works, "remoteness": far, "sites": sites, "power": power, "power_ms": power_ms}
	var b := land.bounds()
	var low := INF
	var high := -INF
	for j in GRID_CELLS:
		for i in GRID_CELLS:
			var h := land.height(b.position.x + (i + 0.5) * b.size.x / GRID_CELLS, b.position.y + (j + 0.5) * b.size.y / GRID_CELLS)
			low = minf(low, h)
			high = maxf(high, h)
	world["low"] = low
	world["high"] = high
	world["built_ms"] = Time.get_ticks_msec() - started
	return world


## Metres along a road or track.
static func track_length(road: Dictionary) -> float:
	var points: PackedVector2Array = road["points"]
	var length := 0.0
	for k in range(1, points.size()):
		length += points[k].distance_to(points[k - 1])
	return length


## Whether a site of `kind` other than `i` and not `dropped` stands within `within` metres
## of site `i`.
static func _near_kept(placed: Array[Dictionary], dropped: Array[int], i: int, kind: String, within: float) -> bool:
	var centre: Vector2 = placed[i]["centre"]
	for j in placed.size():
		if j != i and not dropped.has(j) and placed[j]["kind"] == kind and (placed[j]["centre"] as Vector2).distance_to(centre) <= within:
			return true
	return false


## Drops the sites at `dropped` and renames the remaining tracks after the sites' new places
## in the list (a track is named "<kind> <index>").
static func _renumber_tracks(net: RoadNetwork, sites: MapSites, dropped: Array[int]) -> void:
	var renamed: Dictionary[String, String] = {}
	var kept := 0
	for i in sites.sites().size():
		if dropped.has(i):
			continue
		var kind := str(sites.sites()[i]["kind"])
		renamed["%s %d" % [kind, i]] = "%s %d" % [kind, kept]
		kept += 1
	for road: Dictionary in net.roads():
		if road["kind"] == "track" and renamed.has(str(road["from"])):
			road["from"] = renamed[str(road["from"])]
	sites.drop(dropped)


## A built map drawn `pixels` square: `region` of it (all of it when empty) with `layers`.
static func draw(world: Dictionary, pixels: int, layers: PackedStringArray, region := Rect2()) -> Image:
	if layers.is_empty():
		layers = ALL_LAYERS.split(",")
	var land: WorldLand = world["land"]
	if region.size.x <= 0.0:
		region = land.bounds()
	# Without the earthworks layer the land is drawn as it was before anything shaped it.
	var shaped: Earthworks = world["works"] if layers.has("earthworks") else null
	var image := render(land, maxi(pixels, 16), shaped, region, Vector2(float(world["low"]), float(world["high"])))
	if world["remoteness"] != null and layers.has("remoteness"):
		draw_remoteness(image, world["remoteness"], region)
	if world["zones"] != null and layers.has("zones"):
		draw_zones(image, world["zones"], region)
	if world["net"] != null and layers.has("roads"):
		draw_roads(image, world["net"], layers.has("earthworks"), region)
	if world["sites"] != null and layers.has("sites"):
		draw_sites(image, world["sites"], region)
	if world.get("power") != null and layers.has("power"):
		draw_power(image, world["power"], region)
	if world["places"] != null and layers.has("settlements"):
		draw_settlements(image, world["places"], region)
	return image


## The summary and hover grid for a built map, as `stats` gives them.
static func world_stats(world: Dictionary, layers: PackedStringArray) -> Dictionary:
	var shaped: Earthworks = world["works"] if layers.is_empty() or layers.has("earthworks") else null
	var out := stats(world["land"], world["zones"], world["places"], world["net"], shaped, int(world["built_ms"]))
	if world["sites"] != null:
		var placed: MapSites = world["sites"]
		var parts: Array[String] = []
		var counts := placed.counts()
		for kind: String in counts:
			var c: Vector2i = counts[kind]
			parts.append("%s %d%s" % [kind.replace("_", " "), c.x, "" if c.x >= c.y else " (<%d)" % c.y])
		(out["summary"] as Dictionary)["sites"] = ", ".join(parts)
	if world.get("power") != null:
		var power: MapPower = world["power"]
		var lines := {"high_voltage": 0, "low_voltage": 0}
		for line: Dictionary in power.lines():
			lines[line["kind"]] += 1
		var counts := {"high_voltage": Vector2i(lines["high_voltage"], power.towers("high_voltage").size()), "low_voltage": Vector2i(lines["low_voltage"], power.towers("low_voltage").size())}
		(out["summary"] as Dictionary)["power"] = "%d high-voltage lines, %d pylons; %d pole lines, %d poles; %.0f ms" % [counts["high_voltage"].x, counts["high_voltage"].y, counts["low_voltage"].x, counts["low_voltage"].y, float(world.get("power_ms", 0.0))]
	return out


## The land seen from above, north (-z) up: hill shading over green lowland turning brown
## up high, tinted by biome (dark green woods, yellowed dry grass, grey rock), water blue by
## depth. `region` is the square drawn (all of the map when empty); `heights` the range the
## colours run over (the drawn part's own when zero).
static func render(land: WorldLand, pixels: int, works: Earthworks = null, region := Rect2(), heights_range := Vector2.ZERO) -> Image:
	var b := region if region.size.x > 0.0 else land.bounds()
	var step := b.size.x / pixels
	var heights := PackedFloat32Array()
	heights.resize(pixels * pixels)
	var low := INF
	var high := -INF
	for j in pixels:
		for i in pixels:
			var x := b.position.x + (i + 0.5) * step
			var z := b.position.y + (j + 0.5) * step
			var h := works.height(x, z) if works != null else land.height(x, z)
			heights[j * pixels + i] = h
			low = minf(low, h)
			high = maxf(high, h)
	if heights_range != Vector2.ZERO:
		low = heights_range.x
		high = heights_range.y
	var image := Image.create(pixels, pixels, false, Image.FORMAT_RGB8)
	var light := LIGHT.normalized()
	for j in pixels:
		for i in pixels:
			var h := heights[j * pixels + i]
			var right := heights[j * pixels + mini(i + 1, pixels - 1)]
			var down := heights[mini(j + 1, pixels - 1) * pixels + i]
			var normal := Vector3(h - right, step, h - down).normalized()
			var shade := clampf(0.55 + 0.6 * normal.dot(light), 0.25, 1.15)
			var x := b.position.x + (i + 0.5) * step
			var z := b.position.y + (j + 0.5) * step
			var level := land.water_level(x, z)
			# An embankment can stand above a pond's edge: then it is ground.
			if not is_nan(level) and level > h:
				if land.has_coast() and level == land.sea_level and land.is_sea(x, z):
					image.set_pixel(i, j, SEA_SHALLOW.lerp(SEA_DEEP, clampf((level - h) / SEA_DEEP_AT, 0.0, 1.0)) * lerpf(1.0, shade, 0.3))
				else:
					image.set_pixel(i, j, SHALLOW.lerp(DEEP, clampf((level - h) / DEEP_AT, 0.0, 1.0)))
				continue
			var t := clampf((h - low) / maxf(high - low, 0.001), 0.0, 1.0)
			var ground := LOW.lerp(HIGH, t)
			# The slope and the woods from what this pass already has: each would cost several
			# more noise samples a pixel. The slope spans about WorldLand.GRADE_STEP either side
			# whatever the zoom, so rock does not shift when a close-up replaces the overview.
			var reach := maxi(roundi(WorldLand.GRADE_STEP / step), 1)
			var dx := heights[j * pixels + mini(i + reach, pixels - 1)] - heights[j * pixels + maxi(i - reach, 0)]
			var dz := heights[mini(j + reach, pixels - 1) * pixels + i] - heights[maxi(j - reach, 0) * pixels + i]
			var slope := Vector2(dx, dz).length() / (2.0 * reach * step)
			var woods := land.forest(x, z)
			ground = ground.lerp(DRY, land.dry(x, z, woods) * 0.5)
			ground = ground.lerp(FOREST, woods * 0.85)
			ground = ground.lerp(SAND, land.sand(x, z, slope))
			ground = ground.lerp(ROCK, land.rock(x, z, slope) * 0.8)
			image.set_pixel(i, j, ground * shade)
	return image


## The land tinted by how far it is from people: blue near, red far out.
static func draw_remoteness(image: Image, far: MapRemoteness, region := Rect2()) -> void:
	var b := region if region.size.x > 0.0 else far.zones.land.bounds()
	var pixels := image.get_width()
	var step := b.size.x / pixels
	for j in pixels:
		for i in pixels:
			var x := b.position.x + (i + 0.5) * step
			var z := b.position.y + (j + 0.5) * step
			# Water has no way to it; left as water rather than tinted as remote.
			if str(far.zones.zone_at(x, z).get("kind", "")) == "water":
				continue
			image.set_pixel(i, j, image.get_pixel(i, j).lerp(NEAR.lerp(FAR, far.at(x, z)), TINT))


## Each site's footprint filled in its kind's colour with a dark edge, at least 3 pixels so
## a small one still shows on the whole map.
static func draw_sites(image: Image, placed: MapSites, region := Rect2()) -> void:
	var b := region if region.size.x > 0.0 else placed.remoteness.zones.land.bounds()
	var pixels := image.get_width()
	var step := b.size.x / pixels
	var view := Rect2i(0, 0, pixels, pixels)
	for site: Dictionary in placed.sites():
		var foot: Rect2 = site["footprint"]
		var from := Vector2i(((foot.position - b.position) / step).floor())
		var size := Vector2i(maxi(ceili(foot.size.x / step), 3), maxi(ceili(foot.size.y / step), 3))
		var box := Rect2i(from, size)
		var edge := box.grow(1).intersection(view)
		if edge.size.x > 0 and edge.size.y > 0:
			image.fill_rect(edge, ZONE_EDGE)
		var inside := box.intersection(view)
		if inside.size.x > 0 and inside.size.y > 0:
			image.fill_rect(inside, SITE_COLOURS.get(str(site["kind"]), Color.WHITE))


## Each power line as a line between its towers with a dark dot at each, high-voltage
## thicker; the substation yard as a yellow square edged dark. Only the part of a span inside
## the region drawn is stepped along, so a close-up does not walk whole spans off it.
static func draw_power(image: Image, power: MapPower, region := Rect2()) -> void:
	var b := region if region.size.x > 0.0 else power.land.bounds()
	var pixels := image.get_width()
	var step := b.size.x / pixels
	var view := Rect2i(0, 0, pixels, pixels)
	var dot := func(p: Vector2, half: int, colour: Color) -> void:
		var c := Vector2i(((p - b.position) / step).floor())
		var box := Rect2i(c - Vector2i(half, half), Vector2i(half * 2 + 1, half * 2 + 1)).intersection(view)
		if box.size.x > 0 and box.size.y > 0:
			image.fill_rect(box, colour)
	for line: Dictionary in power.lines():
		var high: bool = line["kind"] == "high_voltage"
		var colour := HIGH_VOLTAGE if high else POLE_LINE
		var points: PackedVector2Array = line["points"]
		for k in range(1, points.size()):
			var shown := MapPower.clip(b.grow(step * 2.0), points[k - 1], points[k])
			if is_nan(shown.x):
				continue
			var from := points[k - 1].lerp(points[k], shown.x)
			var to := points[k - 1].lerp(points[k], shown.y)
			var steps := maxi(ceili(from.distance_to(to) / step), 1)
			for s in steps + 1:
				dot.call(from.lerp(to, float(s) / steps), 1 if high else 0, colour)
		for p in points:
			if b.grow(step * 4.0).has_point(p):
				dot.call(p, 2 if high else 1, TOWER)
	var station := power.substation()
	if not station.is_empty():
		var yard: Rect2 = station["yard"]
		var from := Vector2i(((yard.position - b.position) / step).floor())
		var size := Vector2i(maxi(ceili(yard.size.x / step), 5), maxi(ceili(yard.size.y / step), 5))
		var box := Rect2i(from, size)
		var edge := box.grow(1).intersection(view)
		if edge.size.x > 0 and edge.size.y > 0:
			image.fill_rect(edge, TOWER)
		var inside := box.intersection(view)
		if inside.size.x > 0 and inside.size.y > 0:
			image.fill_rect(inside, HIGH_VOLTAGE)


## Thin dark lines where one zone meets another.
static func draw_zones(image: Image, zones: LandZones, region := Rect2()) -> void:
	var b := region if region.size.x > 0.0 else zones.land.bounds()
	var pixels := image.get_width()
	var step := b.size.x / pixels
	var ids := PackedInt32Array()
	ids.resize(pixels * pixels)
	for j in pixels:
		for i in pixels:
			ids[j * pixels + i] = int(zones.zone_at(b.position.x + (i + 0.5) * step, b.position.y + (j + 0.5) * step).get("id", -1))
	for j in range(1, pixels):
		for i in range(1, pixels):
			var id := ids[j * pixels + i]
			if id == ids[j * pixels + i - 1] and id == ids[(j - 1) * pixels + i]:
				continue
			image.set_pixel(i, j, image.get_pixel(i, j).lerp(ZONE_EDGE, 0.35))


## The city's square in red, towns' in orange (drawn twice as thick as zone lines), the
## camp as a white dot in its pad's white square, the harbour's jetty in brown.
static func draw_settlements(image: Image, places: Settlements, region := Rect2()) -> void:
	var b := region if region.size.x > 0.0 else places.zones.land.bounds()
	var pixels := image.get_width()
	var step := b.size.x / pixels
	var squares: Array = []
	if not places.city().is_empty():
		squares.append([places.city()["footprint"], CITY])
	for t: Dictionary in places.towns():
		squares.append([t["footprint"], TOWN])
	if not places.camp_place().is_empty():
		squares.append([places.camp_place()["footprint"], SPAWN])
	for entry: Array in squares:
		var foot: Rect2 = entry[0]
		var colour: Color = entry[1]
		var x0 := floori((foot.position.x - b.position.x) / step)
		var y0 := floori((foot.position.y - b.position.y) / step)
		var x1 := floori((foot.end.x - b.position.x) / step)
		var y1 := floori((foot.end.y - b.position.y) / step)
		for t in 2:
			for x in range(maxi(x0, 0), mini(x1, pixels - 1) + 1):
				for y: int in [y0 + t, y1 - t]:
					if y >= 0 and y < pixels:
						image.set_pixel(x, y, colour)
			for y in range(maxi(y0, 0), mini(y1, pixels - 1) + 1):
				for x: int in [x0 + t, x1 - t]:
					if x >= 0 and x < pixels:
						image.set_pixel(x, y, colour)
	var harbour := places.harbour()
	if not harbour.is_empty():
		var root: Vector3 = harbour["root"]
		var end: Vector3 = harbour["end"]
		var from := (Vector2(root.x, root.z) - b.position) / step
		var to := (Vector2(end.x, end.z) - b.position) / step
		var steps := maxi(ceili(from.distance_to(to)), 1)
		for k in steps + 1:
			var c := Vector2i(from.lerp(to, float(k) / steps).floor())
			for dj in range(-2, 3):
				for di in range(-2, 3):
					if c.x + di >= 0 and c.y + dj >= 0 and c.x + di < pixels and c.y + dj < pixels:
						image.set_pixel(c.x + di, c.y + dj, HARBOUR)
	var camp := places.camp()
	var ci := floori((camp.x - b.position.x) / step)
	var cj := floori((camp.y - b.position.y) / step)
	for dj in range(-4, 5):
		for di in range(-4, 5):
			if di * di + dj * dj <= 16 and ci + di >= 0 and cj + dj >= 0 and ci + di < pixels and cj + dj < pixels:
				image.set_pixel(ci + di, cj + dj, SPAWN)


## Each road as a dark line as wide as the road (at least a pixel). Up close the points are
## further apart than the road is wide, so each step between them is filled in.
static func draw_roads(image: Image, net: RoadNetwork, earthworks: bool, region := Rect2()) -> void:
	var b := region if region.size.x > 0.0 else net.settlements.zones.land.bounds()
	var pixels := image.get_width()
	var step := b.size.x / pixels
	var view := Rect2i(0, 0, pixels, pixels)
	for road: Dictionary in net.roads():
		var half := maxi(int(float(road["width"]) / step / 2.0), 0)
		var points: PackedVector2Array = road["points"]
		var colours: Array[Color] = []
		colours.resize(points.size())
		colours.fill(TRACK if road["kind"] == "track" or road["kind"] == "lane" else ROAD)
		if earthworks:
			for span: Vector2i in road["tunnels"]:
				for i in range(span.x, span.y + 1):
					colours[i] = TUNNEL
			for span: Vector2i in road["bridges"]:
				for i in range(span.x, span.y + 1):
					colours[i] = BRIDGE
		for k in points.size():
			var from := (points[k] - b.position) / step
			var to := (points[mini(k + 1, points.size() - 1)] - b.position) / step
			var steps := maxi(ceili(from.distance_to(to) / maxf(half, 1.0)), 1)
			for s in steps:
				var c := Vector2i(from.lerp(to, float(s) / steps).floor())
				var dot := Rect2i(c - Vector2i(half, half), Vector2i(half * 2 + 1, half * 2 + 1)).intersection(view)
				if dot.size.x > 0 and dot.size.y > 0:
					image.fill_rect(dot, colours[k])


## An island's land, sea and harbour in a line: land area, islets, sea level, and how far
## the harbour is from the camp and how deep the water at its end.
static func coast_summary(land: WorldLand, zones: LandZones, places: Settlements) -> String:
	var b := land.bounds()
	var dry := 0
	var step := 16.0
	var x := b.position.x + step / 2.0
	while x < b.end.x:
		var z := b.position.y + step / 2.0
		while z < b.end.y:
			if not land.is_sea(x, z):
				dry += 1
			z += step
		x += step
	var out := "land %.2f km2, sea level %.0f m" % [dry * step * step / 1.0e6, land.sea_level]
	if zones != null:
		out += ", %d islets" % zones.zones(&"islet").size()
	if places != null:
		var h := places.harbour()
		if h.is_empty():
			out += ", no harbour"
		else:
			var root: Vector3 = h["root"]
			out += ", harbour %.0f m from the camp, %.0f m jetty to %.1f m of water" % [Vector2(root.x, root.z).distance_to(places.camp()), float(h["length"]), float(h["depth"])]
	return out


## What the viewer shows beside the map: a summary of the land, settlements and roads, and
## a coarse grid of heights and zone kinds for the hover readout.
static func stats(land: WorldLand, zones: LandZones, places: Settlements, net: RoadNetwork, works: Earthworks, built_ms: int) -> Dictionary:
	var summary := {
		"map": "%d m square" % int(land.size),
		"built in": "%d ms" % built_ms,
		"walkable (<0.35)": "%d %%" % roundi(land.walkable_share(16.0, 0.35) * 100.0),
		"near flat (<0.08)": "%d %%" % roundi(land.walkable_share(16.0, 0.08) * 100.0),
		"hillside (>0.2)": "%d %%" % roundi((1.0 - land.walkable_share(16.0, 0.2)) * 100.0),
		"ponds": land.ponds().size(),
	}
	if land.has_coast():
		summary["coast"] = coast_summary(land, zones, places)
	if places != null:
		var city := places.city()
		summary["city"] = "%d m" % int((city["footprint"] as Rect2).size.x) if not city.is_empty() else "none"
		summary["towns"] = ", ".join(places.towns().map(func(t: Dictionary) -> String: return "%d m" % int((t["footprint"] as Rect2).size.x))) if not places.towns().is_empty() else "none"
	if net != null:
		var length := 0.0
		var tunnels := 0
		var bridges := 0
		var steepest := 0.0
		for road: Dictionary in net.roads():
			var points: PackedVector2Array = road["points"]
			var heights: PackedFloat32Array = road["heights"]
			for i in range(1, points.size()):
				var run := points[i].distance_to(points[i - 1])
				length += run
				steepest = maxf(steepest, absf(heights[i] - heights[i - 1]) / run)
			tunnels += (road["tunnels"] as Array).size()
			bridges += (road["bridges"] as Array).size()
		summary["roads"] = "%d, %.2f km" % [net.roads().size(), length / 1000.0]
		summary["steepest road"] = "%.3f" % steepest
		summary["tunnels / bridges"] = "%d / %d" % [tunnels, bridges]
	var b := land.bounds()
	var heights: Array[float] = []
	var kinds: Array[int] = []
	var cell := b.size.x / GRID_CELLS
	for j in GRID_CELLS:
		for i in GRID_CELLS:
			var x := b.position.x + (i + 0.5) * cell
			var z := b.position.y + (j + 0.5) * cell
			heights.append(snappedf(works.height(x, z) if works != null else land.height(x, z), 0.1))
			kinds.append(LandZones.KINDS.find(str(zones.zone_at(x, z).get("kind", ""))) if zones != null else -1)
	return {"summary": summary, "grid": {"left": b.position.x, "top": b.position.y, "size": b.size.x, "cells": GRID_CELLS, "heights": heights, "zones": kinds, "kinds": LandZones.KINDS}}

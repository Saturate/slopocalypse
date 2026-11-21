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
const ALL_LAYERS := "zones,settlements,roads,earthworks,sites"
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
	"water": {"cell": "n", "deepen": "n", "min_depth": "n", "min_area": "n", "max_area": "n", "freeboard": "n"},
	"biomes": {"forest_frequency": "n", "forest_threshold": "n", "dry_frequency": "n", "rock_frequency": "n", "rock_threshold": "n",
		"map_metres_per_texel": "n", "rock_grade_from": "n", "rock_grade_to": "n", "hill_forest": "n", "lowland_forest": "n",
		"woodland_frequency": "n", "rock_patch_frequency": "n"},
	"zones": {"cell": "n", "slope_grade": "n", "flat_grade": "n", "forest_cutoff": "n", "wet_distance": "n", "hilltop_rise": "n",
		"hilltop_ring": "n", "spawn_margin": "n", "spawn_edge": "n", "uses": "d"},
	"settlements": {"city": {"use": "s", "size": "n"}, "town": {"use": "s", "size": "n", "spacing": "n", "max": "n"},
		"camp": {"clearance": "n"}, "edge_margin": "n"},
	"roads": {"kinds": "d", "cost": {"forest": "n", "slope": "n", "wetland": "n", "hilltop": "n", "over_grade": "n"},
		"sample": "n", "profile_window": "n"},
	"earthworks": {"bank_grade": "n", "shoulder": "n", "reach": "n"},
	"remoteness": {"reach": "n", "off_road": "n"},
	"sites": MapSites.SECTION,
}
const ROAD_KIND := {"width": "n", "max_grade": "n", "min_radius": "n", "max_cut": "n", "max_fill": "n"}
## Kinds the road network builds; an edited recipe must still have them.
const ROAD_KINDS: Array[String] = ["highway", "two_lane"]
## Ranges for the fields that set how much work a build is: a cell or step near 0, or a huge
## map, scan or count, would keep a render (and the server's worker) busy for minutes or for
## good (a road sample of 0 never ends). Wide enough for any recipe worth looking at.
const LIMITS := {
	"size": Vector2(256, 4096),
	"water.cell": Vector2(4, 64),
	"zones.cell": Vector2(4, 64),
	"zones.wet_distance": Vector2(0, 200),
	"zones.hilltop_ring": Vector2(0, 400),
	"biomes.map_metres_per_texel": Vector2(1, 32),
	"settlements.town.max": Vector2(0, 16),
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
}
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
	for path: String in LIMITS:
		var value: Variant = _at(recipe, path)
		var limit: Vector2 = LIMITS[path]
		if value != null and (float(value) < limit.x or float(value) > limit.y):
			return "%s: %d to %d" % [path, limit.x, limit.y]
	return ""


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
	var world := {"land": land, "zones": zones, "places": places, "net": net, "works": works, "remoteness": far, "sites": sites}
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
## camp as a white dot.
static func draw_settlements(image: Image, places: Settlements, region := Rect2()) -> void:
	var b := region if region.size.x > 0.0 else places.zones.land.bounds()
	var pixels := image.get_width()
	var step := b.size.x / pixels
	var squares: Array = []
	if not places.city().is_empty():
		squares.append([places.city()["footprint"], CITY])
	for t: Dictionary in places.towns():
		squares.append([t["footprint"], TOWN])
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
		colours.fill(TRACK if road["kind"] == "track" else ROAD)
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

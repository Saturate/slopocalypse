extends SceneTree
## Renders a map recipe's land top-down to a PNG (#427, #428): hill shading over colour by
## height, biomes and water, then the layers asked for (zones, settlements, roads,
## earthworks). Run by tools/map-preview.ts and tools/map-viewer.ts:
##   godot --headless --path . -s res://tools/gd/map_preview.gd -- <recipe path> <seed> <out png> <pixels> [layers] [stats json]
## `layers` is comma separated (all when left out); `stats json` gets a summary and a coarse
## height and zone grid for the viewer's hover. No rendering server needed.

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
const TUNNEL := Color(0.62, 0.3, 0.75)
const BRIDGE := Color(0.55, 0.85, 1.0)
const ALL_LAYERS := "zones,settlements,roads,earthworks"
## Cells a side of the stats grid the viewer reads heights and zones from on hover.
const GRID_CELLS := 128


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		push_error("map_preview: want <recipe> <seed> <out> <pixels>")
		quit(2)
		return
	var file := FileAccess.open(args[0], FileAccess.READ)
	if file == null:
		push_error("map_preview: no recipe at %s" % args[0])
		quit(2)
		return
	var recipe: Variant = JSON.parse_string(file.get_as_text())
	if not recipe is Dictionary:
		push_error("map_preview: %s is not a JSON object" % args[0])
		quit(2)
		return
	var started := Time.get_ticks_msec()
	var land := WorldLand.new(recipe, int(args[1]))
	var pixels := maxi(int(args[3]), 16)
	var layers := (args[4] if args.size() > 4 else ALL_LAYERS).split(",", false)
	var image := render(land, pixels)
	var zones: LandZones = null
	var places: Settlements = null
	var net: RoadNetwork = null
	var zones_cfg: Variant = (recipe as Dictionary).get("zones")
	if zones_cfg is Dictionary:
		zones = LandZones.new(land, zones_cfg)
		var places_cfg: Variant = (recipe as Dictionary).get("settlements")
		if places_cfg is Dictionary:
			places = Settlements.new(zones, places_cfg)
			var roads_cfg: Variant = (recipe as Dictionary).get("roads")
			if roads_cfg is Dictionary:
				net = RoadNetwork.new(places, roads_cfg)
	var built := Time.get_ticks_msec() - started
	if zones != null and layers.has("zones"):
		draw_zones(image, zones)
	if net != null and layers.has("roads"):
		draw_roads(image, net, layers.has("earthworks"))
	if places != null and layers.has("settlements"):
		draw_settlements(image, places)
	if args.size() > 5:
		var out := FileAccess.open(args[5], FileAccess.WRITE)
		if out == null:
			push_error("map_preview: could not write %s" % args[5])
			quit(1)
			return
		# Keys in the order written: the summary reads top to bottom as it was built.
		out.store_string(JSON.stringify(stats(land, zones, places, net, built), "", false))
	var err := image.save_png(args[2])
	if err != OK:
		push_error("map_preview: could not write %s (%d)" % [args[2], err])
		quit(1)
		return
	print("map_preview: wrote %s (%d px, %.1f m a pixel)" % [args[2], pixels, land.size / pixels])
	quit(0)


## The land seen from above, north (-z) up: hill shading over green lowland turning brown
## up high, tinted by biome (dark green woods, yellowed dry grass, grey rock), water blue by
## depth.
static func render(land: WorldLand, pixels: int) -> Image:
	var b := land.bounds()
	var step := b.size.x / pixels
	var heights := PackedFloat32Array()
	heights.resize(pixels * pixels)
	var low := INF
	var high := -INF
	for j in pixels:
		for i in pixels:
			var h := land.height(b.position.x + (i + 0.5) * step, b.position.y + (j + 0.5) * step)
			heights[j * pixels + i] = h
			low = minf(low, h)
			high = maxf(high, h)
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
			if not is_nan(level):
				image.set_pixel(i, j, SHALLOW.lerp(DEEP, clampf((level - h) / DEEP_AT, 0.0, 1.0)))
				continue
			var t := (h - low) / maxf(high - low, 0.001)
			var ground := LOW.lerp(HIGH, t)
			ground = ground.lerp(DRY, land.dry(x, z) * 0.5)
			ground = ground.lerp(FOREST, land.forest(x, z) * 0.85)
			ground = ground.lerp(ROCK, land.rock(x, z) * 0.8)
			image.set_pixel(i, j, ground * shade)
	return image


## Thin dark lines where one zone meets another.
static func draw_zones(image: Image, zones: LandZones) -> void:
	var land := zones.land
	var b := land.bounds()
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
static func draw_settlements(image: Image, places: Settlements) -> void:
	var b := places.zones.land.bounds()
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
		var x0 := int((foot.position.x - b.position.x) / step)
		var y0 := int((foot.position.y - b.position.y) / step)
		var x1 := int((foot.end.x - b.position.x) / step)
		var y1 := int((foot.end.y - b.position.y) / step)
		for t in 2:
			for x in range(x0, x1 + 1):
				for y: int in [y0 + t, y1 - t]:
					if x >= 0 and y >= 0 and x < pixels and y < pixels:
						image.set_pixel(x, y, colour)
			for y in range(y0, y1 + 1):
				for x: int in [x0 + t, x1 - t]:
					if x >= 0 and y >= 0 and x < pixels and y < pixels:
						image.set_pixel(x, y, colour)
	var camp := places.camp()
	var ci := int((camp.x - b.position.x) / step)
	var cj := int((camp.y - b.position.y) / step)
	for dj in range(-4, 5):
		for di in range(-4, 5):
			if di * di + dj * dj <= 16 and ci + di >= 0 and cj + dj >= 0 and ci + di < pixels and cj + dj < pixels:
				image.set_pixel(ci + di, cj + dj, SPAWN)


## Each road as a dark line as wide as the road (at least a pixel).
static func draw_roads(image: Image, net: RoadNetwork, earthworks: bool) -> void:
	var b := net.settlements.zones.land.bounds()
	var pixels := image.get_width()
	var step := b.size.x / pixels
	for road: Dictionary in net.roads():
		var half := maxi(int(float(road["width"]) / step / 2.0), 0)
		var points: PackedVector2Array = road["points"]
		var colours: Array[Color] = []
		colours.resize(points.size())
		colours.fill(ROAD)
		if earthworks:
			for span: Vector2i in road["tunnels"]:
				for i in range(span.x, span.y + 1):
					colours[i] = TUNNEL
			for span: Vector2i in road["bridges"]:
				for i in range(span.x, span.y + 1):
					colours[i] = BRIDGE
		for k in points.size():
			var p := points[k]
			var ci := int((p.x - b.position.x) / step)
			var cj := int((p.y - b.position.y) / step)
			for dj in range(-half, half + 1):
				for di in range(-half, half + 1):
					if ci + di >= 0 and cj + dj >= 0 and ci + di < pixels and cj + dj < pixels:
						image.set_pixel(ci + di, cj + dj, colours[k])


## What the viewer shows beside the map: a summary of the land, settlements and roads, and
## a coarse grid of heights and zone kinds for the hover readout.
static func stats(land: WorldLand, zones: LandZones, places: Settlements, net: RoadNetwork, built_ms: int) -> Dictionary:
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
			heights.append(snappedf(land.height(x, z), 0.1))
			kinds.append(LandZones.KINDS.find(str(zones.zone_at(x, z).get("kind", ""))) if zones != null else -1)
	return {"summary": summary, "grid": {"left": b.position.x, "top": b.position.y, "size": b.size.x, "cells": GRID_CELLS, "heights": heights, "zones": kinds, "kinds": LandZones.KINDS}}

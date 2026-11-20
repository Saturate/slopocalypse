extends SceneTree
## Renders a map recipe's land top-down to a PNG (#427): height as hill shading over a
## colour by height. Run by tools/map-preview.ts:
##   godot --headless --path . -s res://tools/gd/map_preview.gd -- <recipe res path> <seed> <out png> <pixels>
## No rendering server needed: it samples WorldLand and writes the image itself.

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
	var land := WorldLand.new(recipe, int(args[1]))
	var pixels := maxi(int(args[3]), 16)
	var image := render(land, pixels)
	var zones_cfg: Variant = (recipe as Dictionary).get("zones")
	if zones_cfg is Dictionary:
		var zones := LandZones.new(land, zones_cfg)
		draw_zones(image, zones)
		var places_cfg: Variant = (recipe as Dictionary).get("settlements")
		if places_cfg is Dictionary:
			draw_settlements(image, Settlements.new(zones, places_cfg))
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

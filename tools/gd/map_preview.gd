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
		draw_zones(image, LandZones.new(land, zones_cfg))
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


## Thin dark lines where one zone meets another, the city's zone outlined in red, and the
## spawn as a white dot.
static func draw_zones(image: Image, zones: LandZones) -> void:
	var land := zones.land
	var b := land.bounds()
	var pixels := image.get_width()
	var step := b.size.x / pixels
	var city := zones.best(&"city")
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
			var in_city := not city.is_empty() and (id == int(city["id"]) or ids[j * pixels + i - 1] == int(city["id"]) or ids[(j - 1) * pixels + i] == int(city["id"]))
			image.set_pixel(i, j, CITY if in_city else image.get_pixel(i, j).lerp(ZONE_EDGE, 0.35))
	var spawn := zones.spawn()
	var si := int((spawn.x - b.position.x) / step)
	var sj := int((spawn.y - b.position.y) / step)
	for dj in range(-3, 4):
		for di in range(-3, 4):
			if di * di + dj * dj <= 9 and si + di >= 0 and sj + dj >= 0 and si + di < pixels and sj + dj < pixels:
				image.set_pixel(si + di, sj + dj, SPAWN)

extends SceneTree
## Renders a map recipe's land top-down to a PNG (#427): height as hill shading over a
## colour by height. Run by tools/map-preview.ts:
##   godot --headless --path . -s res://tools/gd/map_preview.gd -- <recipe res path> <seed> <out png> <pixels>
## No rendering server needed: it samples WorldLand and writes the image itself.

const LIGHT := Vector3(-0.6, 0.7, -0.4)
const LOW := Color(0.36, 0.52, 0.27)
const HIGH := Color(0.62, 0.55, 0.42)
const SHALLOW := Color(0.36, 0.6, 0.7)
const DEEP := Color(0.12, 0.27, 0.42)
## Metres of water from the shallow tint to the deep one.
const DEEP_AT := 3.0


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
	var err := image.save_png(args[2])
	if err != OK:
		push_error("map_preview: could not write %s (%d)" % [args[2], err])
		quit(1)
		return
	print("map_preview: wrote %s (%d px, %.1f m a pixel)" % [args[2], pixels, land.size / pixels])
	quit(0)


## The land seen from above, north (-z) up: hill shading over green lowland turning brown
## up high, water blue by depth.
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
			image.set_pixel(i, j, LOW.lerp(HIGH, t) * shade)
	return image

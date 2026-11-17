@tool
class_name SteelPlate
extends StyleBox
## A painted steel plate: grain, a bevel (light top and left, dark bottom and right), paint
## chipped off along the edges, a few scratches, optional rivets and a hard drop shadow.
## The chips and scratches are seeded by the plate's size, so a plate looks the same every
## frame and two plates of different sizes don't look copied.

## By path: the project theme loads this at startup, before class names are known on a
## fresh checkout.
const Palette := preload("res://core/ui/ui_palette.gd")

const GRAIN_SIZE := 128
const RIVET_INSET := 11.0
const RIVET_RADIUS := 4.0
## Plates smaller than this on either side get no rivets: they would crowd the content.
const RIVET_MIN_SIDE := 72.0
## One chip per this many pixels of edge.
const CHIP_SPACING := 38.0
const STRIPE_WIDTH := 12.0

@export var fill := Palette.STEEL
## Off draws only the outline (a focus ring over the normal plate).
@export var filled := true
@export var outline := Color(0, 0, 0, 0)
@export var outline_width := 2.0
@export var bevel := 3.0
@export var shadow := Vector2(6, 6)
@export var rivets := false
@export var wear := true
## Hazard stripes down the left edge.
@export var stripe := false

static var _grain: Texture2D


func _init() -> void:
	content_margin_left = 16
	content_margin_right = 16
	content_margin_top = 12
	content_margin_bottom = 12


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	if filled:
		if shadow != Vector2.ZERO:
			rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position + shadow, rect.size), Palette.SHADOW)
		rs.canvas_item_add_rect(to_canvas_item, rect, fill)
		rs.canvas_item_add_texture_rect(to_canvas_item, rect, grain().get_rid(), true)
		var seed_from := int(rect.size.x) * 7919 + int(rect.size.y) * 104729
		if wear:
			_chips(to_canvas_item, rect, seed_from)
		if bevel > 0.0:
			rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position, Vector2(rect.size.x, bevel)), Color(1, 1, 1, 0.16))
			rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position + Vector2(0, bevel), Vector2(bevel, rect.size.y - bevel)), Color(1, 1, 1, 0.08))
			rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position.x, rect.end.y - bevel, rect.size.x, bevel), Color(0, 0, 0, 0.45))
			rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.end.x - bevel, rect.position.y, bevel, rect.size.y - bevel), Color(0, 0, 0, 0.3))
		if stripe:
			_stripes(to_canvas_item, rect)
		if rivets and rect.size.x >= RIVET_MIN_SIDE and rect.size.y >= RIVET_MIN_SIDE:
			for corner: Vector2 in [Vector2(RIVET_INSET, RIVET_INSET), Vector2(rect.size.x - RIVET_INSET, RIVET_INSET), Vector2(RIVET_INSET, rect.size.y - RIVET_INSET), rect.size - Vector2(RIVET_INSET, RIVET_INSET)]:
				var p := rect.position + corner
				rs.canvas_item_add_circle(to_canvas_item, p + Vector2(1, 1.5), RIVET_RADIUS, Color(0, 0, 0, 0.6))
				rs.canvas_item_add_circle(to_canvas_item, p, RIVET_RADIUS, fill.lightened(0.25))
				rs.canvas_item_add_circle(to_canvas_item, p - Vector2(1.2, 1.2), RIVET_RADIUS * 0.45, fill.lightened(0.6))
	if outline.a > 0.0:
		var w := outline_width
		rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position, Vector2(rect.size.x, w)), outline)
		rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position.x, rect.end.y - w, rect.size.x, w), outline)
		rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position.x, rect.position.y + w, w, rect.size.y - 2 * w), outline)
		rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.end.x - w, rect.position.y + w, w, rect.size.y - 2 * w), outline)


func _chips(ci: RID, rect: Rect2, seed_from: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_from
	var perimeter := 2.0 * (rect.size.x + rect.size.y)
	var bare := fill.lerp(Palette.STEEL_BARE, 0.45)
	for i in int(perimeter / CHIP_SPACING):
		var along := rng.randf() * perimeter
		var depth := rng.randf_range(0.0, 2.0)
		var chip := Vector2(rng.randf_range(3.0, 14.0), rng.randf_range(1.0, 3.5))
		var p: Vector2
		if along < rect.size.x:
			p = Vector2(along, depth)
		elif along < 2.0 * rect.size.x:
			p = Vector2(along - rect.size.x, rect.size.y - depth - chip.y)
		elif along < 2.0 * rect.size.x + rect.size.y:
			chip = Vector2(chip.y, chip.x)
			p = Vector2(depth, along - 2.0 * rect.size.x)
		else:
			chip = Vector2(chip.y, chip.x)
			p = Vector2(rect.size.x - depth - chip.x, along - 2.0 * rect.size.x - rect.size.y)
		var r := Rect2(rect.position + p, chip).intersection(rect)
		RenderingServer.canvas_item_add_rect(ci, r, bare)
		# A smaller flake beside most chips, so the wear reads as worn paint, not a dashed line.
		if rng.randf() < 0.6:
			var flake := Rect2(r.position + Vector2(rng.randf_range(-3.0, r.size.x), rng.randf_range(-1.0, r.size.y)), r.size * 0.5).intersection(rect)
			RenderingServer.canvas_item_add_rect(ci, flake, Color(bare, 0.7))
	# Scratches: thin, faint, mostly level.
	for i in int(rect.size.x * rect.size.y / 18000.0):
		var from := rect.position + Vector2(rng.randf() * rect.size.x, rng.randf() * rect.size.y)
		var to := from + Vector2.from_angle(rng.randf_range(-0.5, 0.5)) * rng.randf_range(10.0, 40.0)
		to = to.clamp(rect.position, rect.end)
		RenderingServer.canvas_item_add_line(ci, from, to, Color(1, 1, 1, 0.07), 1.0)


func _stripes(ci: RID, rect: Rect2) -> void:
	var step := 8.0
	var x := rect.position.x
	var y := rect.position.y
	while y < rect.end.y:
		var top := maxf(y - 6.0, rect.position.y)
		var bottom := minf(y + 6.0, rect.end.y)
		var poly := PackedVector2Array([Vector2(x, y), Vector2(x + STRIPE_WIDTH, top), Vector2(x + STRIPE_WIDTH, minf(y, rect.end.y)), Vector2(x, bottom)])
		RenderingServer.canvas_item_add_polygon(ci, poly, PackedColorArray([Palette.INK]))
		y += step


## A tiling speckle of light and dark, drawn over the fill so any fill colour gets the same
## painted-metal grain.
static func grain() -> Texture2D:
	if _grain != null:
		return _grain
	var img := Image.create(GRAIN_SIZE, GRAIN_SIZE, false, Image.FORMAT_RGBA8)
	var coarse := FastNoiseLite.new()
	coarse.seed = 3
	coarse.frequency = 0.05
	var fine := FastNoiseLite.new()
	fine.seed = 7
	fine.frequency = 0.6
	for y in GRAIN_SIZE:
		for x in GRAIN_SIZE:
			# Sampled on a torus so the texture tiles without seams.
			var u := TAU * x / GRAIN_SIZE
			var v := TAU * y / GRAIN_SIZE
			var n := coarse.get_noise_3d(cos(u) * 20.0, sin(u) * 20.0, cos(v) * 20.0 + sin(v) * 7.0) * 0.6 + fine.get_noise_2d(x, y) * 0.4
			var c := Color(1, 1, 1, n * 0.12) if n > 0.0 else Color(0, 0, 0, -n * 0.2)
			img.set_pixel(x, y, c)
	_grain = ImageTexture.create_from_image(img)
	return _grain

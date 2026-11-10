class_name GridPainter
extends RefCounted
## Colours and item tiles for the gear screens.

const GAP := 2
const TEXT := Color(0.88, 0.88, 0.84)
const CELL_COLOUR := Color(0.16, 0.17, 0.16)
const OK := Color(0.4, 0.8, 0.4, 0.35)
const BAD := Color(0.9, 0.35, 0.3, 0.35)
const FLASH := Color(0.95, 0.4, 0.3)


static func draw_tile(canvas: Control, inventory: Node, placed: Dictionary, at: Vector2, w: int, h: int, cell: int, alpha: float) -> void:
	var item := str(placed["item"])
	var info: Dictionary = inventory.call(&"item_info", item)
	var colour: Color = inventory.call(&"kind_colour", str(info.get("kind", "")))
	var rect := Rect2(at + Vector2(GAP, GAP), Vector2(w * cell - GAP * 2, h * cell - GAP * 2))
	var icon: Texture2D = inventory.call(&"item_icon", item) if inventory.has_method(&"item_icon") else null
	# A lighter backing behind a picture, so dark parts stand out; the kind's colour tints it.
	canvas.draw_rect(rect, Color(colour.darkened(0.55) if icon == null else colour.lerp(Color(0.62, 0.63, 0.6), 0.55), alpha * 0.92))
	if icon != null:
		_draw_icon(canvas, icon, rect, bool(placed.get("rotated", false)), alpha)
	canvas.draw_rect(rect, Color(colour, alpha), false, 1.5)
	# Tiles carry the short name, top left, small over the picture; the full name on hover.
	var label := str(info.get("short", info.get("name", item)))
	canvas.draw_string(ThemeDB.fallback_font, rect.position + Vector2(4, 13), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 6, 11, Color(TEXT, alpha * 0.9))


## The picture inside the tile, kept to its aspect; turned a quarter for a turned item (the
## picture was rendered for the item upright).
static func _draw_icon(canvas: Control, icon: Texture2D, rect: Rect2, rotated: bool, alpha: float) -> void:
	var inner := rect.grow(-3.0)
	var size := icon.get_size()
	if rotated:
		size = Vector2(size.y, size.x)
	var fit := minf(inner.size.x / size.x, inner.size.y / size.y)
	var drawn := size * fit
	var centre := inner.get_center()
	if rotated:
		canvas.draw_set_transform(centre, PI / 2.0)
		canvas.draw_texture_rect(icon, Rect2(Vector2(-drawn.y, -drawn.x) / 2.0, Vector2(drawn.y, drawn.x)), false, Color(1, 1, 1, alpha))
		canvas.draw_set_transform(Vector2.ZERO)
	else:
		canvas.draw_texture_rect(icon, Rect2(centre - drawn / 2.0, drawn), false, Color(1, 1, 1, alpha))

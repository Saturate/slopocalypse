class_name GridPainter
extends RefCounted
## Colours and item tiles for the gear screens.

const GAP := 2
const TEXT := UiPalette.TEXT
const CELL_COLOUR := Color(0.16, 0.17, 0.16)
const OK := Color(0.4, 0.8, 0.4, 0.35)
const BAD := Color(0.9, 0.35, 0.3, 0.35)
const FLASH := Color(0.95, 0.4, 0.3)
## A tag's text size and padding: big enough to read at 720p, small enough to leave most of
## a one-cell tile's picture showing; the backing lets the picture show through it too.
const TAG_FONT := 15
const TAG_PAD := 2.0
const TAG_BACK := Color(0.05, 0.05, 0.04, 0.62)


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
	canvas.draw_string(canvas.get_theme_default_font(), rect.position + Vector2(4, 14), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 6, 14, Color(TEXT, alpha * 0.9))


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


## A small dark tag with `text` in the bottom right corner of a tile of w x h cells at `at`
## (a price on the trade screen).
static func draw_tag(canvas: Control, at: Vector2, w: int, h: int, cell: int, text: String, colour: Color) -> void:
	var font := canvas.get_theme_default_font()
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_FONT)
	var corner := at + Vector2(w * cell - GAP, h * cell - GAP)
	var box := Rect2(corner - size - Vector2(TAG_PAD * 2.0, TAG_PAD), size + Vector2(TAG_PAD * 2.0, TAG_PAD))
	canvas.draw_rect(box, TAG_BACK)
	canvas.draw_string(font, Vector2(box.position.x + TAG_PAD, box.end.y - TAG_PAD - font.get_descent(TAG_FONT) + 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_FONT, colour)

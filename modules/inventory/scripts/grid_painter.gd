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
	var info: Dictionary = inventory.call(&"item_info", str(placed["item"]))
	var colour: Color = inventory.call(&"kind_colour", str(info.get("kind", "")))
	var rect := Rect2(at + Vector2(GAP, GAP), Vector2(w * cell - GAP * 2, h * cell - GAP * 2))
	canvas.draw_rect(rect, Color(colour.darkened(0.45), alpha))
	canvas.draw_rect(rect, Color(colour, alpha), false, 1.5)
	# Tiles carry the short name, top left; the full name shows on hover.
	var label := str(info.get("short", info.get("name", placed["item"])))
	canvas.draw_string(ThemeDB.fallback_font, rect.position + Vector2(4, 15), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 6, 13, Color(TEXT, alpha))

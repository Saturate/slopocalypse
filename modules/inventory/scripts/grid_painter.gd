class_name GridPainter
extends RefCounted
## Draws an inventory grid and its item tiles onto a Control, for the inventory and loot
## screens alike.

const GAP := 2
const TEXT := Color(0.88, 0.88, 0.84)
const CELL_COLOUR := Color(0.16, 0.17, 0.16)
const OK := Color(0.4, 0.8, 0.4, 0.35)
const BAD := Color(0.9, 0.35, 0.3, 0.35)
const FLASH := Color(0.95, 0.4, 0.3)


static func draw_cells(canvas: Control, grid: InventoryGrid, cell: int) -> void:
	for y in grid.height():
		for x in grid.width():
			canvas.draw_rect(Rect2(x * cell + GAP, y * cell + GAP, cell - GAP * 2, cell - GAP * 2), CELL_COLOUR)


## Every tile in `grid` except the one with uid `skip` (being dragged); `flash` is a uid to
## outline in red.
static func draw_items(canvas: Control, inventory: Node, grid: InventoryGrid, cell: int, skip: int = -1, flash: int = -1) -> void:
	for placed: Dictionary in grid.items():
		var uid := int(placed["uid"])
		if uid == skip:
			continue
		var at := Vector2(int(placed["x"]), int(placed["y"])) * cell
		draw_tile(canvas, inventory, placed, at, int(placed["w"]), int(placed["h"]), cell, 1.0)
		if uid == flash:
			var rect := Rect2(at + Vector2(GAP, GAP), Vector2(int(placed["w"]) * cell - GAP * 2, int(placed["h"]) * cell - GAP * 2))
			canvas.draw_rect(rect, FLASH, false, 3.0)


static func draw_tile(canvas: Control, inventory: Node, placed: Dictionary, at: Vector2, w: int, h: int, cell: int, alpha: float) -> void:
	var info: Dictionary = inventory.call(&"item_info", str(placed["item"]))
	var colour: Color = inventory.call(&"kind_colour", str(info.get("kind", "")))
	var rect := Rect2(at + Vector2(GAP, GAP), Vector2(w * cell - GAP * 2, h * cell - GAP * 2))
	canvas.draw_rect(rect, Color(colour.darkened(0.45), alpha))
	canvas.draw_rect(rect, Color(colour, alpha), false, 1.5)
	# Tiles carry the short name, top right; the full name shows on hover.
	var label := str(info.get("short", info.get("name", placed["item"])))
	canvas.draw_string(ThemeDB.fallback_font, rect.position + Vector2(4, 14), label, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8, 12, Color(TEXT, alpha))


## Green or red block where a dragged item would land.
static func draw_fit(canvas: Control, cell_at: Vector2i, size: Vector2i, cell: int, fits: bool) -> void:
	canvas.draw_rect(Rect2(Vector2(cell_at) * cell, Vector2(size) * cell), OK if fits else BAD)


## The item covering `at` in `grid`, or empty.
static func item_at(grid: InventoryGrid, at: Vector2i) -> Dictionary:
	if grid == null:
		return {}
	for placed: Dictionary in grid.items():
		if Rect2i(int(placed["x"]), int(placed["y"]), int(placed["w"]), int(placed["h"])).has_point(at):
			return placed
	return {}


## Whether `item` fits anywhere in `grid`, upright or turned.
static func fits_anywhere(grid: InventoryGrid, item: String) -> bool:
	for rotated: bool in [false, true]:
		for y in grid.height():
			for x in grid.width():
				if grid.can_place(item, x, y, rotated, -1):
					return true
	return false

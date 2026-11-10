class_name GearPanel
extends HBoxContainer
## One side of the gear screens: the equipment slots on the left (rig, backpack, and the
## guns, which are not items yet and only show what you have), the grids on the right
## (pockets, then the grids the worn rig and backpack open; a crate shows its one grid).
## Draws itself from an `InventoryGear`; the screen that owns it handles dragging and asks
## `target_at` what is under the mouse.

const CELL := 40
const SLOT_CELLS := 2
const ACCENT := Color(0.82, 0.62, 0.3)
const DIM := Color(0.6, 0.61, 0.58)
const SLOT_COLOUR := Color(0.14, 0.15, 0.14)
const SLOT_EDGE := Color(0.3, 0.31, 0.28)

## Returns the InventoryGear to show (or null).
var gear_source: Callable
var inventory: Node
## Read-only gun slots, `{name: label}`; only your own side shows them.
var weapon_labels: Dictionary = {}
## Uid not to draw (being dragged), and uid to outline in red (refused quick move).
var skip_uid := -1
var flash_uid := -1

var _slots_col: VBoxContainer
var _grids_col: VBoxContainer
## Slot name -> its box; grid name -> its control.
var _slot_views: Dictionary = {}
var _grid_views: Dictionary = {}
var _layout_key := ""


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	_slots_col = VBoxContainer.new()
	_slots_col.add_theme_constant_override("separation", 4)
	add_child(_slots_col)
	_grids_col = VBoxContainer.new()
	_grids_col.add_theme_constant_override("separation", 4)
	add_child(_grids_col)


func gear() -> InventoryGear:
	return gear_source.call() if gear_source.is_valid() else null


## Rebuilds the boxes when what is worn (so which grids exist) changed, then redraws.
func refresh() -> void:
	var g := gear()
	var key := _key_of(g)
	if key != _layout_key:
		_layout_key = key
		_rebuild(g)
	for view: Control in _slot_views.values():
		view.queue_redraw()
	for view: Control in _grid_views.values():
		view.queue_redraw()


static func _key_of(g: InventoryGear) -> String:
	if g == null:
		return ""
	var parts: Array[String] = []
	for slot: Dictionary in g.slots():
		parts.append(str(slot["name"]))
	for name in g.grid_names():
		parts.append("%s:%s" % [name, g.grid_size(name)])
	return ",".join(parts)


func _rebuild(g: InventoryGear) -> void:
	for child in _slots_col.get_children():
		child.queue_free()
	for child in _grids_col.get_children():
		child.queue_free()
	_slot_views.clear()
	_grid_views.clear()
	if g == null:
		return
	for slot: Dictionary in g.slots():
		var name := str(slot["name"])
		_slots_col.add_child(_caption(name.to_upper()))
		var box := Control.new()
		box.custom_minimum_size = Vector2.ONE * CELL * SLOT_CELLS
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		box.draw.connect(_draw_slot.bind(box, name))
		_slots_col.add_child(box)
		_slot_views[name] = box
	for name: String in weapon_labels:
		_slots_col.add_child(_caption(name.to_upper()))
		var gun := Label.new()
		gun.text = str(weapon_labels[name])
		gun.custom_minimum_size = Vector2(CELL * SLOT_CELLS, CELL * 0.8)
		gun.add_theme_font_size_override("font_size", 13)
		gun.add_theme_color_override("font_color", DIM)
		_slots_col.add_child(gun)
	for name in g.grid_names():
		_grids_col.add_child(_caption(name.to_upper()))
		var view := Control.new()
		view.custom_minimum_size = Vector2(g.grid_size(name) * CELL)
		view.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		view.mouse_filter = Control.MOUSE_FILTER_PASS
		view.draw.connect(_draw_grid.bind(view, name))
		_grids_col.add_child(view)
		_grid_views[name] = view


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", ACCENT)
	return l


func _draw_slot(box: Control, name: String) -> void:
	var rect := Rect2(Vector2.ZERO, box.size)
	box.draw_rect(rect.grow(-GridPainter.GAP), SLOT_COLOUR)
	box.draw_rect(rect.grow(-GridPainter.GAP), SLOT_EDGE, false, 1.5)
	var g := gear()
	if g == null:
		return
	for slot: Dictionary in g.slots():
		var worn: Dictionary = slot["item"]
		if str(slot["name"]) != name or worn.is_empty() or int(worn["uid"]) == skip_uid:
			continue
		GridPainter.draw_tile(box, inventory, worn, Vector2.ZERO, SLOT_CELLS, SLOT_CELLS, CELL, 1.0)
		if int(worn["uid"]) == flash_uid:
			box.draw_rect(rect.grow(-GridPainter.GAP), GridPainter.FLASH, false, 3.0)


func _draw_grid(view: Control, name: String) -> void:
	var g := gear()
	if g == null:
		return
	var size := g.grid_size(name)
	for y in size.y:
		for x in size.x:
			view.draw_rect(Rect2(x * CELL + GridPainter.GAP, y * CELL + GridPainter.GAP, CELL - GridPainter.GAP * 2, CELL - GridPainter.GAP * 2), GridPainter.CELL_COLOUR)
	for placed: Dictionary in g.items(name):
		var uid := int(placed["uid"])
		if uid == skip_uid:
			continue
		var at := Vector2(int(placed["x"]), int(placed["y"])) * CELL
		GridPainter.draw_tile(view, inventory, placed, at, int(placed["w"]), int(placed["h"]), CELL, 1.0)
		if uid == flash_uid:
			view.draw_rect(Rect2(at, Vector2(int(placed["w"]), int(placed["h"])) * CELL).grow(-GridPainter.GAP), GridPainter.FLASH, false, 3.0)


## What is under `global`: `{slot: name, view}` or `{grid: name, cell: Vector2i, local, view}`,
## or empty.
func target_at(global: Vector2) -> Dictionary:
	for name: String in _slot_views:
		var box: Control = _slot_views[name]
		if box.get_global_rect().has_point(global):
			return {"slot": name, "view": box}
	for name: String in _grid_views:
		var view: Control = _grid_views[name]
		if view.get_global_rect().has_point(global):
			var local := view.get_global_transform().affine_inverse() * global
			return {"grid": name, "cell": Vector2i(floori(local.x / CELL), floori(local.y / CELL)), "local": local, "view": view}
	return {}


## The item at a place on this side, `{slot}` or `{grid, x, y}`, or empty.
func item_at(place: Dictionary) -> Dictionary:
	var g := gear()
	if g == null:
		return {}
	if place.has("slot"):
		for slot: Dictionary in g.slots():
			if str(slot["name"]) == str(place["slot"]):
				var worn: Dictionary = slot["item"]
				if worn.is_empty():
					return {}
				var out := worn.duplicate()
				var size: Array = (inventory.call(&"item_info", str(worn["item"])) as Dictionary).get("size", [1, 1])
				out.merge({"w": int(size[0]), "h": int(size[1]), "x": 0, "y": 0, "rotated": false, "slot": place["slot"]})
				return out
		return {}
	var at := Vector2i(int(place.get("x", 0)), int(place.get("y", 0)))
	for placed: Dictionary in g.items(str(place.get("grid", ""))):
		if Rect2i(int(placed["x"]), int(placed["y"]), int(placed["w"]), int(placed["h"])).has_point(at):
			var out := placed.duplicate()
			out["grid"] = place["grid"]
			return out
	return {}


func view_of(place: Dictionary) -> Control:
	if place.has("slot"):
		return _slot_views.get(str(place["slot"]))
	return _grid_views.get(str(place.get("grid", "")))

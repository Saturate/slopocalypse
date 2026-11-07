class_name InventoryScreen
extends CanvasLayer
## Client only, local player: the inventory (Tab). The grid with every item as a tile;
## drag a tile to move it, R turns it while dragging, the drop spot shows green or red from
## the same Rust rules the server uses. A move is only a request: the server's answer
## redraws the grid, so a refused one snaps back.

const CELL := 58
const GAP := 2
const BG := Color(0.05, 0.06, 0.06, 0.82)
const PANEL := Color(0.11, 0.12, 0.11, 0.97)
const ACCENT := Color(0.82, 0.62, 0.3)
const TEXT := Color(0.88, 0.88, 0.84)
const DIM := Color(0.6, 0.61, 0.58)
const CELL_COLOUR := Color(0.16, 0.17, 0.16)
const OK := Color(0.4, 0.8, 0.4, 0.35)
const BAD := Color(0.9, 0.35, 0.3, 0.35)

var inventory: Node
var peer := 0

var _root: Control
var _grid_view: Control
var _info: Label
var _dragging: Dictionary = {}
var _drag_rotated := false
## Where in the tile the mouse grabbed it, in cells, so the tile does not jump.
var _grab := Vector2.ZERO


func _ready() -> void:
	layer = 40
	_build_ui()
	_root.visible = false
	EventBus.subscribe(&"inventory.changed", _on_changed)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"inventory.changed", _on_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"inventory"):
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open() and event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key := (event as InputEventKey).keycode
		if key == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		elif key == KEY_R and not _dragging.is_empty():
			_drag_rotated = not _drag_rotated
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if is_open():
		_grid_view.queue_redraw()


func is_open() -> bool:
	return _root.visible


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func open() -> void:
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_grid_view.queue_redraw()


func close() -> void:
	_dragging = {}
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The item under a grid cell, or empty.
func item_at(cell: Vector2i) -> Dictionary:
	var grid: InventoryGrid = inventory.call(&"grid_of", peer)
	if grid == null:
		return {}
	for placed: Dictionary in grid.items():
		var r := Rect2i(int(placed["x"]), int(placed["y"]), int(placed["w"]), int(placed["h"]))
		if r.has_point(cell):
			return placed
	return {}


## Starts dragging the item at `cell` (as a mouse press does).
func pick(cell: Vector2i) -> bool:
	var placed := item_at(cell)
	if placed.is_empty():
		return false
	_dragging = placed
	_drag_rotated = bool(placed["rotated"])
	_grab = Vector2(cell - Vector2i(int(placed["x"]), int(placed["y"]))) + Vector2(0.5, 0.5)
	return true


## Drops what is being dragged with its top left at `cell` (as releasing the mouse does).
func drop(cell: Vector2i) -> void:
	if _dragging.is_empty():
		return
	var uid := int(_dragging["uid"])
	_dragging = {}
	inventory.call(&"request_move", uid, cell.x, cell.y, _drag_rotated)


func _on_changed(p: Dictionary) -> void:
	if int(p.get("peer", -1)) == peer:
		_grid_view.queue_redraw()


func _cell_at(local: Vector2) -> Vector2i:
	return Vector2i(floori(local.x / CELL), floori(local.y / CELL))


func _drop_cell(local: Vector2) -> Vector2i:
	return _cell_at(local - (_grab - Vector2(0.5, 0.5)) * CELL)


func _on_grid_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			pick(_cell_at(mb.position))
		elif not Rect2(Vector2.ZERO, _grid_view.size).has_point(mb.position) and not _dragging.is_empty():
			# Let go outside the backpack: it goes on the ground in front of you.
			var uid := int(_dragging["uid"])
			_dragging = {}
			inventory.call(&"request_drop", uid)
		else:
			drop(_drop_cell(mb.position))
	elif event is InputEventMouseMotion and _dragging.is_empty():
		var placed := item_at(_cell_at((event as InputEventMouseMotion).position))
		_info.text = str((inventory.call(&"item_info", str(placed["item"])) as Dictionary).get("name", "")) if not placed.is_empty() else ""


func _draw_grid() -> void:
	var grid: InventoryGrid = inventory.call(&"grid_of", peer)
	if grid == null:
		return
	for y in grid.height():
		for x in grid.width():
			_grid_view.draw_rect(Rect2(x * CELL + GAP, y * CELL + GAP, CELL - GAP * 2, CELL - GAP * 2), CELL_COLOUR)
	var font := ThemeDB.fallback_font
	for placed: Dictionary in grid.items():
		if not _dragging.is_empty() and int(placed["uid"]) == int(_dragging["uid"]):
			continue
		_draw_tile(placed, Vector2(int(placed["x"]), int(placed["y"])) * CELL, int(placed["w"]), int(placed["h"]), font, 1.0)
	if _dragging.is_empty():
		return
	var mouse := _grid_view.get_local_mouse_position()
	var size := Vector2i(int(_dragging["w"]), int(_dragging["h"]))
	if _drag_rotated != bool(_dragging["rotated"]):
		size = Vector2i(size.y, size.x)
	var cell := _drop_cell(mouse)
	var fits := grid.can_place(str(_dragging["item"]), cell.x, cell.y, _drag_rotated, int(_dragging["uid"]))
	_grid_view.draw_rect(Rect2(Vector2(cell) * CELL, Vector2(size) * CELL), OK if fits else BAD)
	_draw_tile(_dragging, mouse - _grab * CELL, size.x, size.y, font, 0.85)


func _draw_tile(placed: Dictionary, at: Vector2, w: int, h: int, font: Font, alpha: float) -> void:
	var info: Dictionary = inventory.call(&"item_info", str(placed["item"]))
	var colour: Color = inventory.call(&"kind_colour", str(info.get("kind", "")))
	var rect := Rect2(at + Vector2(GAP, GAP), Vector2(w * CELL - GAP * 2, h * CELL - GAP * 2))
	_grid_view.draw_rect(rect, Color(colour.darkened(0.45), alpha))
	_grid_view.draw_rect(rect, Color(colour, alpha), false, 1.5)
	# Tiles carry the short name, top right as in Tarkov; the full name shows on hover.
	var label := str(info.get("short", info.get("name", placed["item"])))
	_grid_view.draw_string(font, rect.position + Vector2(4, 14), label, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8, 12, Color(TEXT, alpha))


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = BG
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = ACCENT.darkened(0.5)
	style.border_width_top = 3
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	head.add_child(_label("BACKPACK", 26, ACCENT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(_label("Drag to move  ·  R turns  ·  drag out to drop  ·  E picks up  ·  B mods your gun", 13, DIM))
	var size: Vector2i = inventory.call(&"grid_size")
	_grid_view = Control.new()
	_grid_view.custom_minimum_size = Vector2(size * CELL)
	_grid_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid_view.draw.connect(_draw_grid)
	_grid_view.gui_input.connect(_on_grid_input)
	col.add_child(_grid_view)
	_info = _label("", 15, TEXT)
	_info.custom_minimum_size.y = 22
	col.add_child(_info)


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l

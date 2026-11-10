class_name LootScreen
extends CanvasLayer
## Client only, local player: the loot screen for a body or crate, your gear on the left and
## theirs on the right. Drag a tile between or within the grids (R turns it while dragging;
## the drop spot shows green or red from the same Rust rules the server uses), Ctrl+click
## sends it to the other side into the first place it fits, and letting go outside both
## grids drops it on the ground. Every move is only a request: the server's answer redraws
## both grids, so a refused move snaps back. Esc, Tab or F closes it.

const CELL := 48
const BG := Color(0.05, 0.06, 0.06, 0.82)
const PANEL := Color(0.11, 0.12, 0.11, 0.97)
const ACCENT := Color(0.82, 0.62, 0.3)
const TEXT := Color(0.88, 0.88, 0.84)
const DIM := Color(0.6, 0.61, 0.58)
const FLASH_SECONDS := 0.5

var inventory: Node
var peer := 0

var _root: Control
## Index 0 is your side, 1 theirs.
var _views: Array[Control] = []
var _theirs_title: Label
var _info: Label
## {placed, theirs} while dragging, else empty.
var _dragging: Dictionary = {}
var _drag_rotated := false
## Where in the tile the mouse grabbed it, in cells, so the tile does not jump.
var _grab := Vector2.ZERO
var _flash_uid := -1
var _flash_left := 0.0


func _ready() -> void:
	# Over the inventory screen and the HUD.
	layer = 41
	_build_ui()
	_root.visible = false
	EventBus.subscribe(&"inventory.loot_changed", _on_loot_changed)
	EventBus.subscribe(&"inventory.loot_closed", _on_loot_closed)
	EventBus.subscribe(&"inventory.changed", _on_changed)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"inventory.loot_changed", _on_loot_changed)
	EventBus.unsubscribe(&"inventory.loot_closed", _on_loot_closed)
	EventBus.unsubscribe(&"inventory.changed", _on_changed)


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_redraw()


## Closes the screen and tells the server.
func close() -> void:
	if not is_open():
		return
	_hide()
	inventory.call(&"request_close_loot")


func _hide() -> void:
	_dragging = {}
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _grid(theirs: bool) -> InventoryGrid:
	return inventory.call(&"loot_grid") if theirs else inventory.call(&"grid_of", peer)


## The item under a cell on one side, or empty.
func item_at(theirs: bool, cell: Vector2i) -> Dictionary:
	return GridPainter.item_at(_grid(theirs), cell)


## Starts dragging the item at `cell` (as a mouse press does).
func pick(theirs: bool, cell: Vector2i) -> bool:
	var placed := item_at(theirs, cell)
	if placed.is_empty():
		return false
	_dragging = {"placed": placed, "theirs": theirs}
	_drag_rotated = bool(placed["rotated"])
	_grab = Vector2(cell - Vector2i(int(placed["x"]), int(placed["y"]))) + Vector2(0.5, 0.5)
	return true


## Drops what is being dragged with its top left at `cell` on one side (as releasing the
## mouse over a grid does).
func drop_on(theirs: bool, cell: Vector2i) -> void:
	if _dragging.is_empty():
		return
	var placed: Dictionary = _dragging["placed"]
	var from_theirs: bool = _dragging["theirs"]
	_dragging = {}
	if not from_theirs and not theirs:
		inventory.call(&"request_move", int(placed["uid"]), cell.x, cell.y, _drag_rotated)
	else:
		inventory.call(&"request_transfer", from_theirs, int(placed["uid"]), theirs, cell.x, cell.y, _drag_rotated)


## Drops what is being dragged on the ground (as letting go outside both grids does).
func drop_outside() -> void:
	if _dragging.is_empty():
		return
	var placed: Dictionary = _dragging["placed"]
	var from_theirs: bool = _dragging["theirs"]
	_dragging = {}
	inventory.call(&"request_drop", int(placed["uid"]), from_theirs)


## Ctrl+click: sends the item at `cell` to the other side into the first place it fits. If
## it fits nowhere nothing is asked and the tile flashes. Returns whether it was asked.
func quick_move(theirs: bool, cell: Vector2i) -> bool:
	var placed := item_at(theirs, cell)
	var other := _grid(not theirs)
	if placed.is_empty() or other == null:
		return false
	if not GridPainter.fits_anywhere(other, str(placed["item"])):
		_flash_uid = int(placed["uid"])
		_flash_left = FLASH_SECONDS
		_redraw()
		return false
	inventory.call(&"request_quick_move", theirs, int(placed["uid"]))
	return true


func _on_loot_changed(p: Dictionary) -> void:
	if int(p.get("peer", -1)) != peer:
		return
	_theirs_title.text = str(inventory.call(&"loot_title"))
	var grid := _grid(true)
	if grid != null:
		_views[1].custom_minimum_size = Vector2(grid.width(), grid.height()) * CELL
	# A drag of an item someone else just took ends here.
	if not _dragging.is_empty() and bool(_dragging["theirs"]) and not _holds(grid, int(_dragging["placed"]["uid"])):
		_dragging = {}
	if bool(p.get("opened", false)):
		open()
	_redraw()


static func _holds(grid: InventoryGrid, uid: int) -> bool:
	if grid == null:
		return false
	for placed: Dictionary in grid.items():
		if int(placed["uid"]) == uid:
			return true
	return false


func _on_loot_closed(p: Dictionary) -> void:
	if int(p.get("peer", -1)) == peer and is_open():
		_hide()


func _on_changed(p: Dictionary) -> void:
	if int(p.get("peer", -1)) == peer and is_open():
		_redraw()


func _redraw() -> void:
	for view in _views:
		view.queue_redraw()


func _process(delta: float) -> void:
	if not is_open():
		return
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash_uid = -1
	_redraw()


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed(&"inventory") or event.is_action_pressed(&"interact"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key := (event as InputEventKey).keycode
		if key == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		elif key == KEY_R and not _dragging.is_empty():
			_drag_rotated = not _drag_rotated
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not _dragging.is_empty():
		var mb := event as InputEventMouseButton
		# Let go wherever the mouse is: over a grid, or outside both onto the ground.
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			var side := _side_at(mb.global_position)
			if side < 0:
				drop_outside()
			else:
				drop_on(side == 1, _drop_cell(_views[side].get_global_transform().affine_inverse() * mb.global_position))
			get_viewport().set_input_as_handled()


## 0 for your grid, 1 for theirs, -1 for neither.
func _side_at(global: Vector2) -> int:
	for i in _views.size():
		if _views[i].get_global_rect().has_point(global):
			return i
	return -1


func _cell_at(local: Vector2) -> Vector2i:
	return Vector2i(floori(local.x / CELL), floori(local.y / CELL))


func _drop_cell(local: Vector2) -> Vector2i:
	return _cell_at(local - (_grab - Vector2(0.5, 0.5)) * CELL)


func _on_grid_input(event: InputEvent, theirs: bool) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return
		if mb.ctrl_pressed:
			quick_move(theirs, _cell_at(mb.position))
		else:
			pick(theirs, _cell_at(mb.position))
	elif event is InputEventMouseMotion and _dragging.is_empty():
		var placed := item_at(theirs, _cell_at((event as InputEventMouseMotion).position))
		_info.text = str((inventory.call(&"item_info", str(placed["item"])) as Dictionary).get("name", "")) if not placed.is_empty() else ""


func _draw_side(theirs: bool) -> void:
	var view := _views[1 if theirs else 0]
	var grid := _grid(theirs)
	if grid == null:
		return
	GridPainter.draw_cells(view, grid, CELL)
	var skip := -1
	if not _dragging.is_empty() and bool(_dragging["theirs"]) == theirs:
		skip = int(_dragging["placed"]["uid"])
	GridPainter.draw_items(view, inventory, grid, CELL, skip, _flash_uid)
	if _dragging.is_empty():
		return
	var placed: Dictionary = _dragging["placed"]
	var size := Vector2i(int(placed["w"]), int(placed["h"]))
	if _drag_rotated != bool(placed["rotated"]):
		size = Vector2i(size.y, size.x)
	var mouse := view.get_local_mouse_position()
	if _side_at(view.get_global_mouse_position()) == (1 if theirs else 0):
		var cell := _drop_cell(mouse)
		var moving := int(placed["uid"]) if bool(_dragging["theirs"]) == theirs else -1
		GridPainter.draw_fit(view, cell, size, CELL, grid.can_place(str(placed["item"]), cell.x, cell.y, _drag_rotated, moving))
	# The dragged tile follows the mouse; the side it came from draws it.
	if bool(_dragging["theirs"]) == theirs:
		GridPainter.draw_tile(view, inventory, placed, mouse - _grab * CELL, size.x, size.y, CELL, 0.85)


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
	col.add_child(_label("Drag to move  ·  R turns  ·  Ctrl+click sends to the other side  ·  drag out to drop  ·  Esc closes", 13, DIM))
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 28)
	col.add_child(sides)
	for theirs: bool in [false, true]:
		var side := VBoxContainer.new()
		side.add_theme_constant_override("separation", 6)
		sides.add_child(side)
		var head := HBoxContainer.new()
		side.add_child(head)
		var title := _label("BACKPACK" if not theirs else "", 24, ACCENT)
		head.add_child(title)
		var view := Control.new()
		view.mouse_filter = Control.MOUSE_FILTER_STOP
		view.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		view.draw.connect(_draw_side.bind(theirs))
		view.gui_input.connect(_on_grid_input.bind(theirs))
		side.add_child(view)
		_views.append(view)
		if theirs:
			_theirs_title = title
			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			head.add_child(spacer)
			var take := Button.new()
			take.text = "Take all"
			take.focus_mode = Control.FOCUS_NONE
			take.pressed.connect(func() -> void: inventory.call(&"request_take_all"))
			head.add_child(take)
	var size: Vector2i = inventory.call(&"grid_size")
	_views[0].custom_minimum_size = Vector2(size * CELL)
	_info = _label("", 15, TEXT)
	_info.custom_minimum_size.y = 22
	col.add_child(_info)


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l

class_name GearScreen
extends CanvasLayer
## Client only, local player: shared by the inventory screen (your gear) and the loot screen
## (your gear and a body's or crate's side by side). Drag an item to a slot or a grid cell (R
## turns it while dragging; the drop shows green or red from the same Rust rules the server
## uses), Ctrl+click sends it to the other side into the first place it fits, letting go
## outside drops it on the ground, right click uses it (a medkit). Every move is only a
## request: the server's answer redraws, so a refused move snaps back.

const BG := Color(0.05, 0.06, 0.06, 0.82)
const PANEL := Color(0.11, 0.12, 0.11, 0.97)
const ACCENT := Color(0.82, 0.62, 0.3)
const TEXT := Color(0.88, 0.88, 0.84)
const DIM := Color(0.6, 0.61, 0.58)
const FLASH_SECONDS := 0.5
const DRAG_ALPHA := 0.9

var inventory: Node
var peer := 0

var _root: Control
var _overlay: Control
## Index 0 is your side; index 1, when there is one, theirs.
var _panels: Array[GearPanel] = []
var _titles: Array[Label] = []
var _info: Label
## {placed, theirs, full} while dragging, else empty.
var _dragging: Dictionary = {}
var _drag_rotated := false
## Where in the item the mouse grabbed it, in cells, so it does not jump.
var _grab := Vector2.ZERO
var _flash_left := 0.0


## Whether this screen has a second side (the loot screen).
func _two_sided() -> bool:
	return false


func _hint() -> String:
	return ""


func _ready() -> void:
	_build_ui()
	_root.visible = false
	EventBus.subscribe(&"inventory.changed", _on_changed)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"inventory.changed", _on_changed)


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func _hide() -> void:
	_dragging = {}
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _gear(theirs: bool) -> InventoryGear:
	return inventory.call(&"loot_grid") if theirs else inventory.call(&"grid_of", peer)


func _panel(theirs: bool) -> GearPanel:
	return _panels[1 if theirs and _panels.size() > 1 else 0]


## The item at a place (`{slot}` or `{grid, x, y}`) on one side, or empty.
func item_at(theirs: bool, place: Dictionary) -> Dictionary:
	return _panel(theirs).item_at(place)


## Starts dragging the item at `place` (as a mouse press does).
func pick(theirs: bool, place: Dictionary) -> bool:
	var placed := item_at(theirs, place)
	if placed.is_empty():
		return false
	var gear := _gear(theirs)
	_dragging = {"placed": placed, "theirs": theirs, "full": gear != null and gear.is_full(int(placed["uid"]))}
	_drag_rotated = bool(placed["rotated"])
	if placed.has("slot"):
		_grab = Vector2(0.5, 0.5)
	else:
		_grab = Vector2(Vector2i(int(place.get("x", 0)), int(place.get("y", 0))) - Vector2i(int(placed["x"]), int(placed["y"]))) + Vector2(0.5, 0.5)
	_refresh()
	return true


## Drops what is being dragged at `place` on one side (a slot, or the top left cell in a
## grid), as releasing the mouse there does.
func drop_on(theirs: bool, place: Dictionary) -> void:
	if _dragging.is_empty():
		return
	var placed: Dictionary = _dragging["placed"]
	var from_theirs: bool = _dragging["theirs"]
	_dragging = {}
	var to := place.duplicate()
	if to.has("grid"):
		to["rotated"] = _drag_rotated
	if not from_theirs and not theirs:
		inventory.call(&"request_move", int(placed["uid"]), to)
	else:
		inventory.call(&"request_transfer", from_theirs, int(placed["uid"]), theirs, to)
	_refresh()


## Drops what is being dragged on the ground (as letting go outside the panels does).
func drop_outside() -> void:
	if _dragging.is_empty():
		return
	var placed: Dictionary = _dragging["placed"]
	var from_theirs: bool = _dragging["theirs"]
	_dragging = {}
	inventory.call(&"request_drop", int(placed["uid"]), from_theirs)
	_refresh()


## Ctrl+click: sends the item at `place` to the other side into the first place it fits. If
## it fits nowhere nothing is asked and it flashes. Returns whether it was asked.
func quick_move(theirs: bool, place: Dictionary) -> bool:
	if not _two_sided():
		return false
	var placed := item_at(theirs, place)
	var gear := _gear(theirs)
	var other := _gear(not theirs)
	if placed.is_empty() or other == null or gear == null:
		return false
	if not _fits_anywhere(other, str(placed["item"]), gear.is_full(int(placed["uid"]))):
		_panel(theirs).flash_uid = int(placed["uid"])
		_flash_left = FLASH_SECONDS
		_refresh()
		return false
	inventory.call(&"request_quick_move", theirs, int(placed["uid"]))
	return true


static func _fits_anywhere(gear: InventoryGear, item: String, full: bool) -> bool:
	for slot: Dictionary in gear.slots():
		if gear.can_place(item, full, {"slot": slot["name"]}, -1):
			return true
	for name in gear.grid_names():
		var size := gear.grid_size(name)
		for rotated: bool in [false, true]:
			for y in size.y:
				for x in size.x:
					if gear.can_place(item, full, {"grid": name, "x": x, "y": y, "rotated": rotated}, -1):
						return true
	return false


func _on_changed(p: Dictionary) -> void:
	if int(p.get("peer", -1)) == peer and is_open():
		_refresh()


func _refresh() -> void:
	for i in _panels.size():
		var panel := _panels[i]
		var dragging_here := not _dragging.is_empty() and bool(_dragging["theirs"]) == (i == 1)
		panel.skip_uid = int(_dragging["placed"]["uid"]) if dragging_here else -1
		panel.refresh()
	_overlay.queue_redraw()


func _process(delta: float) -> void:
	if not is_open():
		return
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			for panel in _panels:
				panel.flash_uid = -1
	_refresh()


## Esc closes; R turns what is dragged. Subclasses add their own keys.
func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key := (event as InputEventKey).keycode
		if key == KEY_ESCAPE:
			_close_requested()
			get_viewport().set_input_as_handled()
		elif key == KEY_R and not _dragging.is_empty():
			_drag_rotated = not _drag_rotated
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_press(mb)
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and not _dragging.is_empty():
			_release(mb.global_position)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var hit := _hit(mb.global_position)
			if not hit.is_empty():
				var used := item_at(hit["theirs"], hit["place"])
				if not used.is_empty() and not bool(hit["theirs"]) and not (inventory.call(&"item_info", str(used["item"])) as Dictionary).get("use", {}).is_empty():
					inventory.call(&"request_use", str(used["item"]))
	elif event is InputEventMouseMotion and _dragging.is_empty():
		var hit := _hit((event as InputEventMouseMotion).global_position)
		var placed := item_at(hit["theirs"], hit["place"]) if not hit.is_empty() else {}
		_info.text = str((inventory.call(&"item_info", str(placed["item"])) as Dictionary).get("name", "")) if not placed.is_empty() else ""


func _close_requested() -> void:
	_hide()


func _press(mb: InputEventMouseButton) -> void:
	var hit := _hit(mb.global_position)
	if hit.is_empty():
		return
	if mb.ctrl_pressed:
		quick_move(hit["theirs"], hit["place"])
	else:
		pick(hit["theirs"], hit["place"])
	get_viewport().set_input_as_handled()


func _release(global: Vector2) -> void:
	var hit := _hit(global, true)
	if hit.is_empty():
		if _over_panel(global):
			# Let go on the panel but not on a slot or cell: nothing happens.
			_dragging = {}
			_refresh()
		else:
			drop_outside()
		return
	drop_on(hit["theirs"], hit["place"])


## `{theirs, place}` for the slot or cell under `global`, or empty. With `for_drop`, a grid
## place is the dragged item's top left, from where it was grabbed.
func _hit(global: Vector2, for_drop: bool = false) -> Dictionary:
	for i in _panels.size():
		var t := _panels[i].target_at(global)
		if t.is_empty():
			continue
		if t.has("slot"):
			return {"theirs": i == 1, "place": {"slot": t["slot"]}}
		var cell: Vector2i = t["cell"]
		if for_drop:
			var local: Vector2 = t["local"]
			var top := local - (_grab - Vector2(0.5, 0.5)) * GearPanel.CELL
			cell = Vector2i(floori(top.x / GearPanel.CELL), floori(top.y / GearPanel.CELL))
		return {"theirs": i == 1, "place": {"grid": t["grid"], "x": cell.x, "y": cell.y}}
	return {}


func _over_panel(global: Vector2) -> bool:
	for panel in _panels:
		if panel.get_global_rect().has_point(global):
			return true
	return false


## The dragged item under the mouse and, over a slot or grid, a green or red block where it
## would land.
func _draw_overlay() -> void:
	if _dragging.is_empty():
		return
	var placed: Dictionary = _dragging["placed"]
	var size := Vector2i(int(placed["w"]), int(placed["h"]))
	if _drag_rotated != bool(placed["rotated"]):
		size = Vector2i(size.y, size.x)
	var mouse := _overlay.get_local_mouse_position()
	var hit := _hit(_overlay.get_global_mouse_position(), true)
	if not hit.is_empty():
		var theirs: bool = hit["theirs"]
		var place: Dictionary = hit["place"]
		var gear := _gear(theirs)
		var view := _panel(theirs).view_of(place)
		if gear != null and view != null:
			var moving := int(placed["uid"]) if theirs == bool(_dragging["theirs"]) else -1
			var to := place.duplicate()
			var origin := view.get_global_rect().position - _overlay.get_global_rect().position
			var block := Rect2(origin, view.size)
			if to.has("grid"):
				to["rotated"] = _drag_rotated
				block = Rect2(origin + Vector2(int(to["x"]), int(to["y"])) * GearPanel.CELL, Vector2(size) * GearPanel.CELL)
			var fits := gear.can_place(str(placed["item"]), bool(_dragging["full"]), to, moving)
			_overlay.draw_rect(block, GridPainter.OK if fits else GridPainter.BAD)
			_overlay.draw_rect(block, (GridPainter.OK if fits else GridPainter.BAD).lightened(0.4), false, 2.0)
	GridPainter.draw_tile(_overlay, inventory, placed, mouse - _grab * GearPanel.CELL, size.x, size.y, GearPanel.CELL, DRAG_ALPHA)


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(_label(_hint(), 14, DIM))
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 40)
	col.add_child(sides)
	for theirs: bool in ([false, true] if _two_sided() else [false]):
		var side := VBoxContainer.new()
		side.add_theme_constant_override("separation", 8)
		sides.add_child(side)
		var head := HBoxContainer.new()
		side.add_child(head)
		var title := _label("YOU" if not theirs else "", 24, ACCENT)
		head.add_child(title)
		_titles.append(title)
		if theirs:
			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			head.add_child(spacer)
			var take := Button.new()
			take.text = "Take all"
			take.focus_mode = Control.FOCUS_NONE
			take.add_theme_font_size_override("font_size", 16)
			take.pressed.connect(func() -> void: inventory.call(&"request_take_all"))
			head.add_child(take)
		var gear_panel := GearPanel.new()
		gear_panel.inventory = inventory
		gear_panel.gear_source = _gear.bind(theirs)
		if not theirs:
			gear_panel.weapon_labels = (inventory.call(&"weapon_labels") as Dictionary)
		side.add_child(gear_panel)
		_panels.append(gear_panel)
	_info = _label("", 16, TEXT)
	_info.custom_minimum_size.y = 24
	col.add_child(_info)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_root.add_child(_overlay)


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l

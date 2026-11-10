class_name MissionBoardScreen
extends CanvasLayer
## Client only, local player: the mission board. Each offered mission is a sheet with its
## name, objective, distance, time limit and pay; "Take this job" makes it the mission for
## the whole group (the server decides). Esc or F closes it.

const BG := Color(0.05, 0.06, 0.06, 0.82)
const PANEL := Color(0.11, 0.12, 0.11, 0.97)
const SHEET := Color(0.16, 0.17, 0.15)
const CHOSEN := Color(0.24, 0.22, 0.14)
const ACCENT := Color(0.82, 0.62, 0.3)
const TEXT := Color(0.9, 0.9, 0.86)
const DIM := Color(0.74, 0.75, 0.71)
const SHEET_WIDTH := 300

var missions: Node

var _root: Control
var _sheets: HBoxContainer


func _ready() -> void:
	layer = 42
	_build_ui()
	_root.visible = false
	EventBus.subscribe(&"missions.board_opened", _on_opened)
	EventBus.subscribe(&"missions.changed", _on_changed)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"missions.board_opened", _on_opened)
	EventBus.unsubscribe(&"missions.changed", _on_changed)


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_refresh()
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Picks offer `index` (as its button does).
func choose(index: int) -> void:
	missions.call(&"request_choose", index)


func _on_opened(_p: Dictionary) -> void:
	open()


func _on_changed(_p: Dictionary) -> void:
	if is_open():
		_refresh()


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed(&"interact") or (event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE):
		close()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	for child in _sheets.get_children():
		child.queue_free()
	var offers: Array = missions.get(&"offers")
	var current: Dictionary = missions.get(&"current")
	var running := str(missions.get(&"state")) != "home"
	for i in offers.size():
		var offer: Dictionary = offers[i]
		var chosen := offer == current
		_sheets.add_child(_sheet(i, offer, chosen, running))


func _sheet(index: int, offer: Dictionary, chosen: bool, running: bool) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CHOSEN if chosen else SHEET
	style.border_color = ACCENT if chosen else SHEET.lightened(0.15)
	style.set_border_width_all(2)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.x = SHEET_WIDTH
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	col.add_child(_label(str(offer.get("name", "")), 22, ACCENT))
	var objective := _label(str(offer.get("objective", "")), 15, TEXT)
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.custom_minimum_size.x = SHEET_WIDTH - 32
	col.add_child(objective)
	col.add_child(_label("%d m down the road" % int(offer.get("distance", 0)), 15, DIM))
	col.add_child(_label("Time limit %d:%02d once you arrive" % [int(offer.get("time_limit", 0)) / 60, int(offer.get("time_limit", 0)) % 60], 15, DIM))
	col.add_child(_label("Pays %d kr" % int(offer.get("payout", 0)), 18, TEXT))
	var take := Button.new()
	take.focus_mode = Control.FOCUS_NONE
	take.add_theme_font_size_override("font_size", 16)
	if chosen:
		col.add_child(_label("ACCEPTED: ride out from the car", 16, ACCENT))
		return panel
	elif running:
		take.text = "A run is on"
		take.disabled = true
	else:
		take.text = "Take this job"
		take.pressed.connect(choose.bind(index))
	col.add_child(take)
	return panel


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
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	col.add_child(_label("MISSION BOARD", 28, ACCENT))
	col.add_child(_label("Pick a job for the group, then ride out from the car.  Esc closes.", 14, DIM))
	_sheets = HBoxContainer.new()
	_sheets.add_theme_constant_override("separation", 16)
	col.add_child(_sheets)


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l

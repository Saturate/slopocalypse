class_name MissionBoardScreen
extends CanvasLayer
## Client only, local player: the mission board. Each offered mission is a sheet with its
## name, objective, distance, time limit and pay; "Take this job" makes it the mission for
## the whole group (the server decides). Esc or F closes it.

const BG := UiPalette.BACKDROP
const ACCENT := UiPalette.ACCENT
const TEXT := UiPalette.TEXT
const DIM := UiPalette.DIM
const SHEET_WIDTH := 300

var missions: Node

var _root: Control
var _sheets: HBoxContainer


func _ready() -> void:
	layer = UiLayers.MISSION_BOARD
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
	UiStack.push(self)


func close() -> void:
	_root.visible = false
	UiStack.pop(self)


## Picks offer `index` (as its button does).
func choose(index: int) -> void:
	missions.call(&"request_choose", index)


func _on_opened(_p: Dictionary) -> void:
	open()


func _on_changed(_p: Dictionary) -> void:
	if is_open():
		_refresh()


func _input(event: InputEvent) -> void:
	if not UiStack.is_top(self):
		return
	if event.is_action_pressed(&"interact") or UiStack.is_cancel(event):
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
	# A raised plate on the board; the chosen one ringed in the accent.
	var plate := SteelPlate.new()
	plate.fill = UiPalette.STEEL_RAISED.lightened(0.05) if chosen else UiPalette.STEEL_RAISED
	plate.shadow = Vector2(4, 4)
	plate.outline = ACCENT if chosen else Color(0, 0, 0, 0)
	plate.content_margin_left = 16
	plate.content_margin_right = 16
	plate.content_margin_top = 14
	plate.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", plate)
	panel.custom_minimum_size.x = SHEET_WIDTH
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	col.add_child(_label(str(offer.get("codename", "")), 20, ACCENT))
	col.add_child(_label("%s  ·  %s" % [str(offer.get("type_name", "")).to_upper(), offer.get("place", "")], 14, TEXT))
	var objective := _label(str(offer.get("objective", "")), 15, TEXT)
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.custom_minimum_size.x = SHEET_WIDTH - 32
	col.add_child(objective)
	# A site's distance is from the camp as the crow flies; a roadside spot's is along the highway.
	var at_site := not (offer.get("site", {}) as Dictionary).is_empty()
	col.add_child(_label(("%d m from camp" if at_site else "%d m down the highway") % int(offer.get("distance", 0)), 15, DIM))
	if offer.has("time_limit"):
		col.add_child(_label("Time limit %d:%02d once you arrive" % [int(offer["time_limit"]) / 60, int(offer["time_limit"]) % 60], 15, DIM))
	if offer.has("guards"):
		col.add_child(_label("About %d guards" % int(offer["guards"]), 15, DIM))
	col.add_child(_label("Pays %d tokens" % int(offer.get("payout", 0)), 18, TEXT))
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
	return UiText.label(text, size, colour)

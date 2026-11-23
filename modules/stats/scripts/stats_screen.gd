class_name StatsScreen
extends CanvasLayer
## Client: your kill stats, from the Esc menu, as the server last sent them.

const WIDTH := 480.0
## Rows shown, in order: [key, label]. Soldier kills by faction follow the soldier total.
const ROWS := [
	["kills.soldier", "Soldiers"],
	["kills.player", "Players"],
	["kills.drone", "Drones"],
	["kills.civilian", "Civilians"],
	["headshots", "Headshots"],
	["longest_kill", "Longest kill"],
	["deaths", "Deaths"],
]

var stats_module: Node

var _frame: ScreenFrame
var _grid: GridContainer


func _ready() -> void:
	layer = UiLayers.MENU_SCREENS
	_frame = ScreenFrame.new("STATS", WIDTH)
	_frame.visible = false
	add_child(_frame)
	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.columns = 2
	_grid.add_theme_constant_override(&"h_separation", 24)
	_grid.add_theme_constant_override(&"v_separation", 8)
	_frame.content.add_child(_grid)
	_frame.add_hint(&"ui_cancel", "Back")


func open() -> void:
	_refresh()
	_frame.visible = true
	UiStack.push(self)


func close() -> void:
	_frame.visible = false
	UiStack.pop(self)


func is_open() -> bool:
	return _frame.visible


func _input(event: InputEvent) -> void:
	if is_open() and UiStack.is_top(self) and UiStack.is_cancel(event):
		close()
		get_viewport().set_input_as_handled()


## The value shown for `key`, as text.
static func shown(values: Dictionary, key: String) -> String:
	var v := float(values.get(key, 0.0))
	if key == KillStats.LONGEST:
		return "%d m" % roundi(v)
	return "%d" % roundi(v)


func _refresh() -> void:
	for child in _grid.get_children():
		child.queue_free()
	var values: Dictionary = stats_module.get(&"mine")
	for row: Array in ROWS:
		_row(str(row[1]), shown(values, str(row[0])), false)
		if str(row[0]) == "kills.soldier":
			var factions: Array = []
			for key: String in values:
				if key.begins_with("kills.soldier."):
					factions.append(key)
			factions.sort()
			for key: String in factions:
				_row("    " + key.trim_prefix("kills.soldier.").capitalize(), shown(values, key), true)


func _row(label: String, value: String, minor: bool) -> void:
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = WIDTH * 0.6
	if minor:
		l.theme_type_variation = &"HintLabel"
	_grid.add_child(l)
	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Out to the panel's right edge, under the scroll area's width.
	v.custom_minimum_size.x = WIDTH * 0.4 - 24.0
	v.theme_type_variation = &"HintLabel" if minor else &""
	if not minor:
		v.add_theme_color_override(&"font_color", UiPalette.ACCENT)
	_grid.add_child(v)

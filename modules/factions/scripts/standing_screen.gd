class_name StandingScreen
extends CanvasLayer
## Client: how each faction sees you, from the Esc menu. A bar per faction from -100 to 100
## with its band (hostile, neutral, friendly, allied). Reads the standing the server sent.

const WIDTH := 560.0

var factions: Node

var _frame: ScreenFrame
var _rows: VBoxContainer


func _ready() -> void:
	layer = UiLayers.MENU_SCREENS
	_frame = ScreenFrame.new("STANDING", WIDTH)
	_frame.visible = false
	add_child(_frame)
	var hint := Label.new()
	hint.theme_type_variation = &"HintLabel"
	hint.text = "How each faction sees you. Killing their soldiers lowers it; killing their enemies raises it."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = WIDTH - 40.0
	_frame.content.add_child(hint)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override(&"separation", 14)
	_frame.content.add_child(_rows)
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


## {faction: value}: what the server sent, or everyone's starting standing before it has.
func values() -> Dictionary:
	var mine: Dictionary = factions.get(&"my_standing")
	if not mine.is_empty():
		return mine
	var rules: FactionRules = factions.get(&"rules")
	return rules.standing_of("")


func _refresh() -> void:
	for child in _rows.get_children():
		child.queue_free()
	var rules: FactionRules = factions.get(&"rules")
	var all := values()
	for id: String in rules.ids():
		var value := float(all.get(id, rules.start_standing(id)))
		var band := rules.band(value)
		var row := VBoxContainer.new()
		var head := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = str(rules.info(id).get("name", id)).to_upper()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name_label)
		var band_label := Label.new()
		band_label.name = "Band"
		band_label.text = "%s  %+d" % [band.to_upper(), int(value)]
		band_label.add_theme_color_override(&"font_color", colour_of(band))
		head.add_child(band_label)
		row.add_child(head)
		var bar := StandingBar.new()
		bar.value = value
		bar.colour = colour_of(band)
		bar.custom_minimum_size = Vector2(WIDTH - 40.0, 18)
		row.add_child(bar)
		_rows.add_child(row)


static func colour_of(band: String) -> Color:
	match band:
		"hostile":
			return UiPalette.BAD
		"friendly", "allied":
			return UiPalette.GOOD
	return UiPalette.WARN


## A -100..100 bar filled from the middle toward the value.
class StandingBar:
	extends Control
	var value := 0.0
	var colour := Color.WHITE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(Rect2(r.position + Vector2(0, 3), r.size), Color(0, 0, 0, 0.5))
		draw_rect(r, Color(0.08, 0.08, 0.07, 0.85))
		var mid := r.size.x / 2.0
		var len := mid * absf(value) / 100.0
		var fill := Rect2(mid if value >= 0.0 else mid - len, 0, len, r.size.y)
		draw_rect(fill, colour)
		draw_rect(Rect2(fill.position, Vector2(fill.size.x, 3)), colour.lightened(0.3))
		draw_rect(Rect2(mid - 1, -4, 2, r.size.y + 8), UiPalette.TEXT)

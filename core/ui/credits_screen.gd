class_name CreditsScreen
extends ScreenFrame
## Who made the game and what it is made with. Scrolls slowly on its own until the player
## scrolls or drags it themselves.

const WIDTH := 760.0
## Pixels a second at the 1600x900 base.
const ROLL_SPEED := 28.0
## A pause at the top before rolling starts.
const ROLL_DELAY := 1.5

var _roll := 0.0
var _rolling := true
var _waited := 0.0


func _init(people: Dictionary = Credits.people(), parts: Array[Dictionary] = Credits.third_party()) -> void:
	super("CREDITS", WIDTH)
	name = "Credits"
	content.add_child(_line(str(people.get("note", "")), &"HintLabel"))
	_section("PEOPLE")
	for person: Variant in people.get("people", []):
		var p: Dictionary = person
		content.add_child(_line(str(p.get("name", ""))))
		content.add_child(_line(str(p.get("role", "")), &"HintLabel"))
	_section("AGENTS")
	for agent: Variant in people.get("agents", []):
		content.add_child(_line(str(agent)))
	_section("MADE WITH")
	for part: Dictionary in parts:
		content.add_child(_line(str(part["what"])))
		content.add_child(_line("%s  ·  %s" % [part["licence"], part["source"]], &"HintLabel"))
	add_hint(&"ui_cancel", "Back")
	scroll.gui_input.connect(_on_scroll_input)


func _process(delta: float) -> void:
	if not visible or not _rolling:
		return
	_waited += delta
	if _waited < ROLL_DELAY:
		return
	_roll += ROLL_SPEED * delta
	scroll.scroll_vertical = int(_roll)


## Rolled back to the top each time the screen opens.
func restart() -> void:
	_roll = 0.0
	_waited = 0.0
	_rolling = true
	scroll.scroll_vertical = 0


func is_rolling() -> bool:
	return _rolling


func _on_scroll_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenDrag or event is InputEventPanGesture:
		_rolling = false


func _section(title: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 14
	content.add_child(gap)
	content.add_child(_line(title, &"HeadingLabel"))


func _line(text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 40.0
	return l

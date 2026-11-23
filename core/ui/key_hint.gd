class_name KeyHint
extends HBoxContainer
## A key cap and what it does ("[F] Trade"). The cap shows the key bound to `action` now,
## read from the InputMap, so it is right after a rebind and on any keyboard layout. With no
## action it is just the text (a prompt like "Choose a mission at the board first").

var action: StringName = &""
var text := "":
	set(value):
		text = value
		if _label != null:
			_label.text = value

var _cap: Label
var _label: Label


func _init(for_action: StringName = &"", what := "") -> void:
	action = for_action
	text = what
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 8)
	_cap = Label.new()
	_cap.theme_type_variation = &"TapeLabel"
	_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_cap)
	_label = Label.new()
	_label.theme_type_variation = &"HudLabel"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.text = text
	add_child(_label)
	refresh()


## Reads the binding again (after a rebind).
func refresh() -> void:
	_cap.text = key_for(action) if action != &"" else ""
	_cap.visible = action != &""


## The name of the first key or button bound to `action`, as the player's keyboard labels
## it; "?" when nothing is bound.
static func key_for(for_action: StringName) -> String:
	if for_action == &"ui_cancel":
		return "Esc"
	if not InputMap.has_action(for_action):
		return "?"
	for ev: InputEvent in InputMap.action_get_events(for_action):
		if ev is InputEventKey:
			var key := ev as InputEventKey
			var code := key.keycode
			if key.physical_keycode != KEY_NONE:
				code = key.physical_keycode
				# The layout's own label for that key position; headless has no layout and
				# errors if asked.
				if DisplayServer.get_name() != "headless":
					var mapped := DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
					if mapped != KEY_NONE:
						code = mapped
			if code != KEY_NONE:
				return OS.get_keycode_string(code)
		elif ev is InputEventMouseButton:
			match (ev as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT:
					return "LMB"
				MOUSE_BUTTON_RIGHT:
					return "RMB"
				MOUSE_BUTTON_MIDDLE:
					return "MMB"
	return "?"


## For a line of hints in plain text: "F" for interact, so "%s  Trade" reads "F  Trade".
static func inline(for_action: StringName, what: String) -> String:
	return "%s  %s" % [key_for(for_action), what]

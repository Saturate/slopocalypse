class_name SettingsScreen
extends ScreenFrame
## Mouse sensitivity, field of view, volume, UI scale, fullscreen, blood and key bindings. Changes
## apply at once and are saved when the screen closes. Keys are listed for the actions the
## running game has registered, so the list is full in a session and empty on the title
## (modules register their keys when they load).
##
## Opens from the title and from the Esc menu; Esc closes it (or cancels a key being bound).

signal closed

const WIDTH := 620.0
## Actions that are the engine's own (menus, text fields), not the game's.
const HIDDEN_PREFIX := "ui_"

var _waiting_for := ""
var _key_buttons: Dictionary[String, Button] = {}
var _sliders: Dictionary[String, HSlider] = {}
var _fullscreen: Button
var _blood: Button
var _compass: Button
var _coop_marker: Button


func _init() -> void:
	super("SETTINGS", WIDTH)
	name = "Settings"
	visible = false
	_slider("mouse_scale", "Mouse sensitivity", Settings.MOUSE_MIN, Settings.MOUSE_MAX, 0.05, func(v: float) -> String: return "%.2fx" % v)
	_slider("fov_offset", "Field of view", Settings.FOV_MIN, Settings.FOV_MAX, 1.0, func(v: float) -> String: return "%+d°" % int(v))
	_slider("volume", "Volume", 0.0, 1.0, 0.05, func(v: float) -> String: return "%d %%" % roundi(v * 100.0))
	_slider("ui_scale", "Interface size", Settings.UI_MIN, Settings.UI_MAX, 0.05, func(v: float) -> String: return "%d %%" % roundi(v * 100.0))
	_fullscreen = _toggle("Fullscreen", "fullscreen")
	# Read by the gore module as blood shows; nothing for the engine to apply. Without the
	# module the toggle would do nothing, so it isn't offered.
	_blood = _toggle("Blood", "blood")
	_blood.visible = Features.is_enabled(&"gore")
	# Read by the compass module each frame; offered only with it.
	_compass = _toggle("Compass", "compass")
	_compass.visible = Features.is_enabled(&"compass")
	# Read by the coop_marker module each frame; offered only with it.
	_coop_marker = _toggle("Partner marker", "coop_marker")
	_coop_marker.visible = Features.is_enabled(&"coop_marker")
	var keys_head := Label.new()
	keys_head.theme_type_variation = &"HeadingLabel"
	keys_head.text = "KEYS"
	content.add_child(keys_head)
	var keys := GridContainer.new()
	keys.name = "Keys"
	# Two actions a row, so the list uses the panel's width.
	keys.columns = 4
	keys.add_theme_constant_override(&"h_separation", 16)
	content.add_child(keys)
	var reset := Button.new()
	reset.name = "Reset"
	reset.text = "Back to defaults"
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(_reset)
	content.add_child(reset)
	add_hint(&"ui_cancel", "Back")


func open() -> void:
	_refresh()
	visible = true
	UiStack.push(self)


func close() -> void:
	_waiting_for = ""
	visible = false
	UiStack.pop(self)
	Settings.save()
	closed.emit()


func is_waiting_for_key() -> bool:
	return not _waiting_for.is_empty()


## Starts binding `action`: the next key pressed becomes its key.
func listen_for(action: String) -> void:
	_waiting_for = action
	_key_buttons[action].text = "Press a key..."


func _input(event: InputEvent) -> void:
	if not visible or not UiStack.is_top(self):
		return
	if is_waiting_for_key():
		var key := event as InputEventKey
		if key == null or not key.pressed or key.echo:
			return
		get_viewport().set_input_as_handled()
		var action := _waiting_for
		_waiting_for = ""
		# Esc cancels; it stays the menu key.
		if key.physical_keycode != KEY_ESCAPE:
			Settings.bind(action, key.physical_keycode)
		_refresh()
		return
	if UiStack.is_cancel(event):
		close()
		get_viewport().set_input_as_handled()


func _slider(key: String, label: String, low: float, high: float, step: float, shown: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	# Room for the scroll bar on the right.
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size.x = 190
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.name = key
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 84
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	slider.value_changed.connect(func(v: float) -> void:
		Settings.set_value(key, v)
		value_label.text = shown.call(v)
		_apply())
	var pad := Control.new()
	pad.custom_minimum_size.x = 12
	row.add_child(pad)
	content.add_child(row)
	_sliders[key] = slider


func _refresh() -> void:
	for key: String in _sliders:
		_sliders[key].set_value_no_signal(float(Settings.value(key)))
		_sliders[key].value_changed.emit(_sliders[key].value)
	for toggle: Button in [_fullscreen, _blood, _compass, _coop_marker]:
		toggle.set_pressed_no_signal(bool(Settings.value(String(toggle.get_meta(&"setting")))))
		_show_toggle(toggle)
	var keys := content.get_node(^"Keys") as GridContainer
	for child in keys.get_children():
		child.queue_free()
	_key_buttons.clear()
	var actions: Array[String] = []
	for action: StringName in InputMap.get_actions():
		if not String(action).begins_with(HIDDEN_PREFIX):
			actions.append(String(action))
	actions.sort()
	if actions.is_empty():
		var note := Label.new()
		note.theme_type_variation = &"HintLabel"
		note.text = "Keys can be changed once you're in a game."
		keys.add_child(note)
		return
	for action in actions:
		var l := Label.new()
		l.text = action.capitalize()
		l.custom_minimum_size.x = 150
		keys.add_child(l)
		var b := Button.new()
		b.name = action
		b.text = KeyHint.key_for(StringName(action))
		b.custom_minimum_size = Vector2(110, 36)
		b.pressed.connect(listen_for.bind(action))
		keys.add_child(b)
		_key_buttons[action] = b


## An on/off setting as a toggle button named `label` that says its state: the engine's
## switch icon is too small to read.
func _toggle(label: String, key: String) -> Button:
	var button := Button.new()
	button.name = label
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.custom_minimum_size = Vector2(220, 40)
	button.set_meta(&"setting", key)
	button.toggled.connect(func(on: bool) -> void:
		Settings.set_value(key, on)
		_show_toggle(button)
		_apply())
	content.add_child(button)
	return button


func _show_toggle(button: Button) -> void:
	var on := button.button_pressed
	button.text = "%s: %s" % [button.name, "On" if on else "Off"]
	button.theme_type_variation = &"AccentButton" if on else &""


func _reset() -> void:
	Settings.reset()
	_apply()
	_refresh()


func _apply() -> void:
	if is_inside_tree():
		Settings.apply(get_tree().root)

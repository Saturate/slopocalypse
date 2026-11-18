class_name SessionOverlay
extends CanvasLayer
## Over a running session: a "connecting" card until the server answers (with Cancel, since
## a wrong address can take a while to time out), and the Esc panel to resume, go back to the
## spawn, leave to the menu or quit. Only added for a player at the keyboard.

## Solo connects in a blink; the card only shows if it takes longer than this.
const CONNECTING_DELAY := 0.6

var _waited := 0.0
var _paused := false
var _connecting: Control
var _connecting_label: Label
var _pause: Control
var _host_info: Label
var _settings: SettingsScreen
var _leave: Button


func _ready() -> void:
	layer = UiLayers.SESSION
	add_to_group(&"session_overlay")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_connecting = _card()
	var waiting: VBoxContainer = _connecting.get_meta(&"col")
	_connecting_label = _text(waiting, "", 18, MainMenu.TEXT)
	_add_button(waiting, &"Cancel", "Cancel", func() -> void: Net.leave())
	_pause = _card()
	var col: VBoxContainer = _pause.get_meta(&"col")
	# Solo runs its own server, so nothing stops while this is open.
	var title := _text(col, "MENU", 0, MainMenu.ACCENT)
	title.theme_type_variation = &"TitleLabel"
	title.remove_theme_font_size_override("font_size")
	title.remove_theme_color_override("font_color")
	_text(col, "The world keeps running", 16, MainMenu.DIM)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	col.add_child(gap)
	_host_info = _text(col, "", 14, MainMenu.DIM)
	_add_button(col, &"Resume", "Resume", _resume)
	_add_button(col, &"Settings", "Settings", func() -> void: _settings.open())
	# Unstuck: the player module asks the server to put us back at the spawn.
	_add_button(col, &"BackToSpawn", "Back to spawn", func() -> void:
		EventBus.publish(&"session.back_to_spawn", {})
		_resume())
	_leave = _add_button(col, &"Leave", "Leave to menu", func() -> void: Net.leave())
	_add_button(col, &"Quit", "Quit game", func() -> void: get_tree().quit(0))
	_connecting.visible = false
	_pause.visible = false
	_settings = SettingsScreen.new()
	add_child(_settings)


## Esc opens this only when no other screen is open; another screen on top takes Esc
## itself, so it closes first.
func _input(event: InputEvent) -> void:
	if not UiStack.is_cancel(event):
		return
	if _paused and UiStack.is_top(self):
		_resume()
		get_viewport().set_input_as_handled()
	elif not UiStack.is_blocking():
		_paused = true
		UiStack.push(self)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var up := Net.is_session_connected()
	_waited = 0.0 if up else _waited + delta
	_connecting.visible = not up and _waited > CONNECTING_DELAY
	_connecting_label.text = "Connecting to %s:%d..." % [Net.host, Net.port]
	_pause.visible = _paused and up
	if Net.hosting_port > 0:
		var mine := MainMenu.rank_addresses(IP.get_local_addresses())
		_host_info.text = "Hosting. Friends join at %s:%d" % [mine[0] if not mine.is_empty() else "your address", Net.hosting_port]
	_host_info.visible = Net.hosting_port > 0


## For modules: an entry in the Esc menu, above "Leave to menu" (factions adds Standing).
func add_menu_entry(id: StringName, text: String, on_press: Callable) -> Button:
	var col := _leave.get_parent() as VBoxContainer
	var b := _add_button(col, id, text, on_press)
	col.move_child(b, _leave.get_index())
	return b


func is_paused() -> bool:
	return _paused


func _resume() -> void:
	_paused = false
	UiStack.pop(self)


## A centred card over a dim shade; returns its root, whose "col" meta is the column to fill.
func _card() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade := ColorRect.new()
	shade.color = UiPalette.BACKDROP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 300
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	root.set_meta(&"col", col)
	add_child(root)
	return root


func _text(col: VBoxContainer, text: String, size: int, color: Color) -> Label:
	var l := UiText.label(text, size, color)
	col.add_child(l)
	return l


func _add_button(col: VBoxContainer, id: StringName, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.name = String(id)
	b.text = text
	b.custom_minimum_size.y = 40
	b.pressed.connect(on_press)
	col.add_child(b)
	return b

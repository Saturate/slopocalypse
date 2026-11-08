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


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_connecting = _card()
	var waiting: VBoxContainer = _connecting.get_meta(&"col")
	_connecting_label = _text(waiting, "", 18, MainMenu.TEXT)
	_add_button(waiting, &"Cancel", "Cancel", func() -> void: Net.leave())
	_pause = _card()
	var col: VBoxContainer = _pause.get_meta(&"col")
	_text(col, "PAUSED", 24, MainMenu.ACCENT)
	_host_info = _text(col, "", 14, MainMenu.DIM)
	_add_button(col, &"Resume", "Resume", _resume)
	# Unstuck: the player module asks the server to put us back at the spawn.
	_add_button(col, &"BackToSpawn", "Back to spawn", func() -> void:
		EventBus.publish(&"session.back_to_spawn", {})
		_resume())
	_add_button(col, &"Leave", "Leave to menu", func() -> void: Net.leave())
	_add_button(col, &"Quit", "Quit game", func() -> void: get_tree().quit(0))
	_connecting.visible = false
	_pause.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo() and (event as InputEventKey).keycode == KEY_ESCAPE:
		if _paused:
			_resume()
			get_viewport().set_input_as_handled()
		else:
			_paused = true


func _process(delta: float) -> void:
	var up := Net.is_session_connected()
	_waited = 0.0 if up else _waited + delta
	_connecting.visible = not up and _waited > CONNECTING_DELAY
	_connecting_label.text = "Connecting to %s:%d..." % [Net.host, Net.port]
	# Clicking back into the game recaptures the mouse; the panel follows.
	if _paused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_paused = false
	_pause.visible = _paused and up
	if Net.hosting_port > 0:
		var mine := MainMenu.rank_addresses(IP.get_local_addresses())
		_host_info.text = "Hosting. Friends join at %s:%d" % [mine[0] if not mine.is_empty() else "your address", Net.hosting_port]
	_host_info.visible = Net.hosting_port > 0


func is_paused() -> bool:
	return _paused


func _resume() -> void:
	_paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## A centred card over a dim shade; returns its root, whose "col" meta is the column to fill.
func _card() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = MainMenu.PANEL
	style.border_color = MainMenu.ACCENT.darkened(0.5)
	style.border_width_top = 3
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 300
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	root.set_meta(&"col", col)
	add_child(root)
	return root


func _text(col: VBoxContainer, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
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

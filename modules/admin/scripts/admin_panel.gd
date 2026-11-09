extends CanvasLayer
## Client-only: the admin panel, opened with the toggle key (F2) when the server says this
## player is an admin. Every button asks the server; nothing here changes the game itself.

## Set by the admin module before this enters the tree.
var admin: Node

var _root: PanelContainer
var _players_box: HFlowContainer
var _god: CheckButton
var _key: int = KEY_F2


func _ready() -> void:
	layer = 40
	_key = OS.find_keycode_from_string(str(admin.get(&"config").get("toggle_key", "F2")))
	_build()
	_root.visible = false
	admin.connect(&"status_changed", func(on: bool) -> void:
		if not on:
			close())
	admin.connect(&"players_changed", _show_players)
	admin.connect(&"god_changed", func(on: bool) -> void: _god.set_pressed_no_signal(on))


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not _root.visible:
		return
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == _key and bool(admin.get(&"is_admin_here")):
		if is_open():
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE and is_open():
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	_root = PanelContainer.new()
	_root.name = "Root"
	_root.anchor_left = 1.0
	_root.anchor_right = 1.0
	_root.offset_left = -360.0
	_root.offset_right = -16.0
	_root.offset_top = 16.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.08, 0.92)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	_root.add_theme_stylebox_override(&"panel", style)
	add_child(_root)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	_root.add_child(col)
	_label(col, "ADMIN", 20, MainMenu.ACCENT)

	_label(col, "Time of day", 14, MainMenu.DIM)
	var hours := _row(col)
	for hour: Variant in admin.get(&"config").get("hours", []):
		var h := float(hour)
		_button(hours, "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)], func() -> void: admin.call(&"ask", "hour", {"hour": h}))

	_label(col, "You", 14, MainMenu.DIM)
	var me := _row(col)
	_button(me, "Heal", func() -> void: admin.call(&"ask", "heal"))
	_god = CheckButton.new()
	_god.text = "God mode"
	_god.toggled.connect(func(on: bool) -> void: admin.call(&"ask", "god", {"on": on}))
	me.add_child(_god)

	_label(col, "Teleport", 14, MainMenu.DIM)
	var go := _row(col)
	_button(go, "Spawn", func() -> void: admin.call(&"ask", "teleport", {"to": "spawn"}))
	_button(go, "Car", func() -> void: admin.call(&"ask", "teleport", {"to": "car"}))
	_button(go, "Ahead %d m" % int(admin.get(&"config").get("teleport_ahead", 50.0)), func() -> void: admin.call(&"ask", "teleport", {"to": "ahead"}))
	_players_box = _row(col)

	_label(col, "Spawn in front of you", 14, MainMenu.DIM)
	var spawn := _row(col)
	for kind: String in ["drone", "squad", "crate", "loot", "car"]:
		_button(spawn, kind.capitalize(), func() -> void: admin.call(&"ask", "spawn", {"kind": kind}))

	var key := PlayerProfile.load_from().key
	_label(col, "Your player key (for admin.json on a server): %s" % key, 11, MainMenu.DIM).autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_label(col, "%s or Esc closes" % OS.get_keycode_string(_key), 11, MainMenu.DIM)


## Teleport buttons for everyone else on the server.
func _show_players(names: Dictionary) -> void:
	for child in _players_box.get_children():
		child.queue_free()
	for peer: Variant in names:
		if int(peer) == multiplayer.get_unique_id():
			continue
		var target := "player:%d" % int(peer)
		_button(_players_box, "To %s" % str(names[peer]), func() -> void: admin.call(&"ask", "teleport", {"to": target}))


func _row(parent: Container) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override(&"h_separation", 6)
	row.add_theme_constant_override(&"v_separation", 6)
	parent.add_child(row)
	return row


func _button(parent: Container, text: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	for state: StringName in [&"normal", &"hover", &"pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = {&"normal": Color(1, 1, 1, 0.07), &"hover": Color(1, 1, 1, 0.16), &"pressed": MainMenu.ACCENT.darkened(0.4)}[state]
		box.set_corner_radius_all(4)
		box.content_margin_left = 10.0
		box.content_margin_right = 10.0
		box.content_margin_top = 4.0
		box.content_margin_bottom = 4.0
		b.add_theme_stylebox_override(state, box)
	b.pressed.connect(pressed)
	parent.add_child(b)
	return b


func _label(parent: Container, text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", colour)
	parent.add_child(l)
	return l

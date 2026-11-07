class_name MainMenu
extends Control
## The first screen of a windowed game: play solo, host for friends, or join a server by
## address. It only turns clicks into a choice; Boot starts the session. Built in code
## because it lives in core, which loads before any module and has no builder pipeline.

signal solo_requested
signal host_requested(port: int)
signal join_requested(host: String, port: int)

const BG := Color(0.07, 0.08, 0.08)
const PANEL := Color(0.12, 0.13, 0.12, 0.96)
const ACCENT := Color(0.82, 0.62, 0.3)
const TEXT := Color(0.86, 0.86, 0.82)
const DIM := Color(0.55, 0.56, 0.53)
const WARN := Color(0.95, 0.45, 0.35)
const LABEL := Color(0.66, 0.67, 0.63)
const BUTTON := Color(0.17, 0.18, 0.17)
const BUTTON_HOVER := Color(0.22, 0.23, 0.21)
const BORDER := Color(0.32, 0.33, 0.3)
const WIDTH := 420.0
const SHOWN_SERVERS := 4

## Why the last session ended; shown above the buttons.
var message := ""
var servers: ServerList
var save_path := ServerList.SAVE_PATH

var _address: LineEdit
var _port: LineEdit
var _message: Label
var _buttons: Dictionary[StringName, Button] = {}


## Local IPv4 addresses friends could reach, Tailscale's 100.64.0.0/10 first since that is
## the address that works across the internet.
static func rank_addresses(all: PackedStringArray) -> Array[String]:
	var tailscale: Array[String] = []
	var other: Array[String] = []
	for a in all:
		if ":" in a or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		var parts := a.split(".")
		if parts.size() == 4 and parts[0] == "100" and int(parts[1]) >= 64 and int(parts[1]) < 128:
			tailscale.append(a)
		else:
			other.append(a)
	return tailscale + other


func _ready() -> void:
	if servers == null:
		servers = ServerList.load_from(save_path)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = ACCENT.darkened(0.5)
	style.border_width_top = 3
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = WIDTH
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	col.add_child(_label("OUTPOST", 46, ACCENT))
	col.add_child(_label("Co-op survival for friends", 16, DIM))

	var solo := _button(&"Solo", "Play solo", func() -> void: solo_requested.emit(), true)
	col.add_child(solo)
	col.add_child(_gap())

	col.add_child(_label("PLAY WITH FRIENDS", 14, LABEL))
	var host := _button(&"Host", "Host a game", func() -> void: host_requested.emit(_port_value()))
	col.add_child(host)
	var info_row := HBoxContainer.new()
	var mine := rank_addresses(IP.get_local_addresses())
	var share := _label("Friends join at  %s" % mine[0] if not mine.is_empty() else "Friends join at your address", 15, TEXT)
	share.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_row.add_child(share)
	if not mine.is_empty():
		var copy := _button(&"Copy", "Copy", func() -> void: DisplayServer.clipboard_set(_share_address(mine[0])))
		copy.custom_minimum_size = Vector2(64, 30)
		copy.add_theme_font_size_override("font_size", 14)
		info_row.add_child(copy)
	info_row.add_child(_label("port", 14, LABEL))
	_port = LineEdit.new()
	_port.text = str(NetSession.DEFAULT_PORT)
	_port.custom_minimum_size.x = 64
	_port.max_length = 5
	info_row.add_child(_port)
	col.add_child(info_row)
	col.add_child(_label("Send that address to friends; they paste it under Join.", 14, LABEL))
	col.add_child(_gap())

	col.add_child(_label("JOIN A FRIEND", 14, LABEL))
	var join_row := HBoxContainer.new()
	_address = LineEdit.new()
	_address.placeholder_text = "address, e.g. 100.101.102.103"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.custom_minimum_size.y = 40
	_address.text_submitted.connect(func(_t: String) -> void: _join(_address.text))
	_address.text_changed.connect(func(_t: String) -> void: _message.visible = false)
	join_row.add_child(_address)
	var join := _button(&"Join", "Join", func() -> void: _join(_address.text))
	join.custom_minimum_size.x = 96
	join_row.add_child(join)
	col.add_child(join_row)
	_message = _label(message, 15, WARN)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.visible = not message.is_empty()
	col.add_child(_message)
	var known := servers.addresses()
	if not known.is_empty():
		_address.text = known[0]
		col.add_child(_label("Recent (click to join)", 14, LABEL))
	var recent := VBoxContainer.new()
	recent.add_theme_constant_override("separation", 0)
	col.add_child(recent)
	for i in mini(known.size(), SHOWN_SERVERS):
		var address := known[i]
		var b := Button.new()
		b.name = "Server%d" % i
		b.text = address
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 30
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_color", TEXT)
		b.add_theme_stylebox_override("normal", _style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
		b.add_theme_stylebox_override("hover", _style(BUTTON_HOVER, ACCENT.darkened(0.3)))
		b.add_theme_stylebox_override("pressed", _style(BUTTON_HOVER, ACCENT))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.pressed.connect(func() -> void: _join(address))
		recent.add_child(b)
	col.add_child(_gap())
	var quit := _button(&"Quit", "Quit", func() -> void: get_tree().quit(0))
	quit.custom_minimum_size = Vector2(120, 34)
	quit.size_flags_horizontal = Control.SIZE_SHRINK_END
	quit.add_theme_font_size_override("font_size", 15)
	col.add_child(quit)


func button(id: StringName) -> Button:
	return _buttons.get(id)


func address_field() -> LineEdit:
	return _address


func message_label() -> Label:
	return _message


func _join(text: String) -> void:
	var a := ServerList.parse_address(text)
	if not a["ok"]:
		_show("That does not look like an address. Use host or host:port, e.g. 100.101.102.103.")
		return
	servers.remember(text.strip_edges())
	servers.save(save_path)
	join_requested.emit(a["host"], a["port"])


func _show(text: String) -> void:
	_message.text = text
	_message.visible = true


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A bordered button; the primary one is filled amber so the main action stands out.
func _button(id: StringName, text: String, on_press: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.name = String(id)
	b.text = text
	b.custom_minimum_size.y = 46
	b.add_theme_font_size_override("font_size", 19)
	if primary:
		b.add_theme_stylebox_override("normal", _style(ACCENT.darkened(0.15), ACCENT))
		b.add_theme_stylebox_override("hover", _style(ACCENT, ACCENT.lightened(0.3)))
		b.add_theme_stylebox_override("pressed", _style(ACCENT.darkened(0.3), ACCENT))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(state, BG)
	else:
		b.add_theme_stylebox_override("normal", _style(BUTTON, BORDER))
		b.add_theme_stylebox_override("hover", _style(BUTTON_HOVER, ACCENT.darkened(0.2)))
		b.add_theme_stylebox_override("pressed", _style(BUTTON_HOVER, ACCENT))
		b.add_theme_color_override("font_color", TEXT)
	b.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), ACCENT.darkened(0.2)))
	b.pressed.connect(on_press)
	_buttons[id] = b
	return b


static func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = fill
	st.border_color = border
	st.set_border_width_all(1)
	st.set_corner_radius_all(2)
	st.set_content_margin_all(8)
	return st


func _port_value() -> int:
	var p := _port.text.to_int()
	return p if p >= 1024 and p <= 65535 else NetSession.DEFAULT_PORT


func _share_address(ip: String) -> String:
	var p := _port_value()
	return ip if p == NetSession.DEFAULT_PORT else "%s:%d" % [ip, p]


func _gap() -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = 6
	return c

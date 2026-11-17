class_name MainMenu
extends Control
## The title screen of a windowed game: the logo and the main choices down the left (play
## solo, play with friends, the test range, the asset library, quit), your name in the top
## right (what a server saves your progress under), and why the last session ended under
## the logo. "Play with friends" opens a screen over it for hosting and joining. It only
## turns clicks into a choice; Boot starts the session. Built in code because it lives in
## core, which loads before any module and has no builder pipeline.

signal solo_requested
signal host_requested(port: int)
signal join_requested(host: String, port: int)
signal library_requested
signal range_requested

const BG := UiPalette.BACKGROUND
const ACCENT := UiPalette.ACCENT
const TEXT := UiPalette.TEXT
const DIM := UiPalette.DIM
const WARN := UiPalette.BAD
const LABEL := UiPalette.DIM
const SHOWN_SERVERS := 4
const MARGIN := Vector2(96, 72)
const BUTTON_SIZE := Vector2(360, 54)
const LOGO_SIZE := 104
const WHATS_NEW_LINES := 3
const WHATS_NEW_WIDTH := 460.0

## Why the last session ended; shown above the buttons.
var message := ""
var servers: ServerList
var save_path := ServerList.SAVE_PATH
var profile_path := PlayerProfile.FILE
## Set by boot when the asset library module is there; shows its button.
var has_library := false
## Set by boot when the test range module is there and on; shows its button.
var has_range := false

var _name: LineEdit
var _address: LineEdit
var _port: LineEdit
var _message: Label
var _friend_message: Label
var _friends: ScreenFrame
var _changelog: ChangelogScreen
var _credits: CreditsScreen
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
	_backdrop()
	_title_column()
	_name_corner()
	_whats_new()
	_friends_screen()
	_changelog = ChangelogScreen.new()
	_credits = CreditsScreen.new()
	for frame: ScreenFrame in [_changelog, _credits]:
		frame.visible = false
		add_child(frame)


## Esc closes whichever of this menu's screens is on top.
func _input(event: InputEvent) -> void:
	if not UiStack.is_cancel(event):
		return
	for frame: ScreenFrame in [_friends, _changelog, _credits]:
		if frame.visible and UiStack.is_top(frame):
			if frame == _friends:
				close_friends()
			else:
				_close(frame)
			get_viewport().set_input_as_handled()
			return


func _exit_tree() -> void:
	for frame: ScreenFrame in [_friends, _changelog, _credits]:
		UiStack.pop(frame)


func open_changelog() -> void:
	_open(_changelog)


func open_credits() -> void:
	_credits.restart()
	_open(_credits)


## Which of the menu's screens is open over the title, or "".
func open_screen() -> String:
	for frame: ScreenFrame in [_friends, _changelog, _credits]:
		if frame.visible:
			return frame.name
	return ""


func _open(frame: ScreenFrame) -> void:
	frame.visible = true
	UiStack.push(frame)


func _close(frame: ScreenFrame) -> void:
	frame.visible = false
	UiStack.pop(frame)


## Bottom right: the newest release and its first few changes; a click opens the changelog.
func _whats_new() -> void:
	var releases := Changelog.load_releases()
	if releases.is_empty():
		return
	var newest: Dictionary = releases[0]
	var card := PanelContainer.new()
	card.name = "WhatsNew"
	card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.offset_right = -MARGIN.x
	card.offset_bottom = -MARGIN.y
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = "Open the changelog"
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			open_changelog())
	add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	var head := Label.new()
	head.theme_type_variation = &"HeadingLabel"
	head.text = "WHAT'S NEW  v%s" % newest["version"]
	col.add_child(head)
	var changes: Array[String] = newest["changes"]
	for i in mini(WHATS_NEW_LINES, changes.size()):
		# Bullet in its own column so a wrapped line indents under the text.
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dot := Label.new()
		dot.text = "·"
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(dot)
		var l := Label.new()
		l.text = changes[i]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = WHATS_NEW_WIDTH
		l.max_lines_visible = 2
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_WORD_ELLIPSIS
		row.add_child(l)
		col.add_child(row)
	var more := Label.new()
	more.theme_type_variation = &"HintLabel"
	more.text = "Click for the full changelog"
	col.add_child(more)


## A dark field with the steel grain and a vignette, behind the title.
func _backdrop() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var grain := TextureRect.new()
	grain.texture = SteelPlate.grain()
	grain.stretch_mode = TextureRect.STRETCH_TILE
	grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grain.modulate = Color(1, 1, 1, 0.5)
	add_child(grain)
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.75))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.35, 0.45)
	t.fill_to = Vector2(1.1, 1.1)
	shade.texture = t
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)


func _title_column() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = MARGIN.x
	col.offset_top = MARGIN.y
	col.offset_bottom = -MARGIN.y
	col.add_theme_constant_override(&"separation", 10)
	add_child(col)
	var logo := Label.new()
	logo.name = "Logo"
	logo.text = "SLOPOCALYPSE"
	logo.theme_type_variation = &"TitleLabel"
	logo.add_theme_font_size_override(&"font_size", LOGO_SIZE)
	col.add_child(logo)
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	# Set by changesetter on release; a build from before the first release shows no number.
	var tagline := "Solo or with friends. Built by agents, mostly."
	var line := Label.new()
	line.add_theme_font_size_override(&"font_size", 22)
	line.text = tagline + ("   v" + version if not version.is_empty() else "")
	col.add_child(line)
	_message = Label.new()
	_message.add_theme_color_override(&"font_color", WARN)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.x = BUTTON_SIZE.x * 1.6
	_message.text = message
	_message.visible = not message.is_empty()
	col.add_child(_message)
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(push)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 12)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(buttons)
	buttons.add_child(_button(&"Solo", "Play solo", func() -> void:
		if _keep_name():
			solo_requested.emit(), true))
	buttons.add_child(_button(&"Friends", "Play with friends", open_friends))
	if has_range:
		buttons.add_child(_button(&"Range", "Test range", func() -> void: range_requested.emit()))
	if has_library:
		buttons.add_child(_button(&"Library", "Asset library", func() -> void: library_requested.emit()))
	buttons.add_child(_button(&"Changelog", "Changelog", open_changelog))
	buttons.add_child(_button(&"Credits", "Credits", open_credits))
	buttons.add_child(_button(&"Quit", "Quit", func() -> void: get_tree().quit(0)))
	(_buttons[&"Solo"] as Button).grab_focus.call_deferred()


## Your name, top right: what servers keep your gear under.
func _name_corner() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.offset_right = -MARGIN.x
	box.offset_top = MARGIN.y
	add_child(box)
	var head := Label.new()
	head.theme_type_variation = &"HintLabel"
	head.text = "PLAYING AS"
	box.add_child(head)
	_name = LineEdit.new()
	_name.name = "Name"
	_name.text = PlayerProfile.load_from(profile_path).name
	_name.max_length = 16
	_name.custom_minimum_size = Vector2(260, 44)
	_name.text_changed.connect(func(_t: String) -> void: _message.visible = false)
	box.add_child(_name)
	var why := Label.new()
	why.theme_type_variation = &"HintLabel"
	why.text = "Servers keep your gear under this name."
	box.add_child(why)


func _friends_screen() -> void:
	_friends = ScreenFrame.new("PLAY WITH FRIENDS", 600.0)
	_friends.name = "Friends"
	_friends.visible = false
	add_child(_friends)
	var col := _friends.content
	col.add_child(_button(&"Host", "Host a game", func() -> void:
		if _keep_name():
			host_requested.emit(_port_value()), true))
	var info_row := HBoxContainer.new()
	var mine := rank_addresses(IP.get_local_addresses())
	var share := Label.new()
	share.text = "Friends join at  %s" % mine[0] if not mine.is_empty() else "Friends join at your address"
	share.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_row.add_child(share)
	if not mine.is_empty():
		var copy := _button(&"Copy", "Copy", func() -> void: DisplayServer.clipboard_set(_share_address(mine[0])))
		copy.custom_minimum_size = Vector2(80, 36)
		info_row.add_child(copy)
	col.add_child(info_row)
	var port_row := HBoxContainer.new()
	port_row.add_theme_constant_override(&"separation", 10)
	var port_label := Label.new()
	port_label.text = "Port"
	port_row.add_child(port_label)
	_port = LineEdit.new()
	_port.text = str(NetSession.DEFAULT_PORT)
	_port.custom_minimum_size.x = 96
	_port.max_length = 5
	port_row.add_child(_port)
	col.add_child(port_row)
	col.add_child(_small("Send that address to friends; they paste it under Join."))
	col.add_child(_gap())
	col.add_child(_small("JOIN A FRIEND"))
	var join_row := HBoxContainer.new()
	_address = LineEdit.new()
	_address.placeholder_text = "address, e.g. 100.101.102.103"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.custom_minimum_size.y = 44
	_address.text_submitted.connect(func(_t: String) -> void: _join(_address.text))
	_address.text_changed.connect(func(_t: String) -> void: _friend_message.visible = false)
	join_row.add_child(_address)
	var join := _button(&"Join", "Join", func() -> void: _join(_address.text))
	join.custom_minimum_size = Vector2(110, 44)
	join_row.add_child(join)
	col.add_child(join_row)
	_friend_message = Label.new()
	_friend_message.add_theme_color_override(&"font_color", WARN)
	_friend_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_friend_message.visible = false
	col.add_child(_friend_message)
	var known := servers.addresses()
	if not known.is_empty():
		_address.text = known[0]
		col.add_child(_small("Recent (click to join)"))
	for i in mini(known.size(), SHOWN_SERVERS):
		var address := known[i]
		var b := Button.new()
		b.name = "Server%d" % i
		b.text = address
		b.custom_minimum_size.y = 38
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void: _join(address))
		col.add_child(b)
	_friends.add_hint(&"ui_cancel", "Back")


func open_friends() -> void:
	_friends.visible = true
	UiStack.push(_friends)
	(_buttons[&"Host"] as Button).grab_focus.call_deferred()


func close_friends() -> void:
	_friends.visible = false
	UiStack.pop(_friends)
	(_buttons[&"Friends"] as Button).grab_focus.call_deferred()


func friends_open() -> bool:
	return _friends.visible


func button(id: StringName) -> Button:
	return _buttons.get(id)


func address_field() -> LineEdit:
	return _address


func name_field() -> LineEdit:
	return _name


## Saves the typed name for the next join; false (with a message) if it is blank.
func _keep_name() -> bool:
	var typed := _name.text.strip_edges()
	if typed.is_empty():
		_show("Type a name first: servers keep your gear under it.")
		return false
	var profile := PlayerProfile.load_from(profile_path)
	if profile.name != typed:
		profile.name = typed
		profile.save(profile_path)
	return true


func message_label() -> Label:
	return _message


func _join(text: String) -> void:
	if not _keep_name():
		return
	var a := ServerList.parse_address(text)
	if not a["ok"]:
		_show("That does not look like an address. Use host or host:port, e.g. 100.101.102.103.")
		return
	servers.remember(text.strip_edges())
	servers.save(save_path)
	join_requested.emit(a["host"], a["port"])


## On the title, and on the friends screen too when it is open over it.
func _show(text: String) -> void:
	_message.text = text
	_message.visible = true
	_friend_message.text = text
	_friend_message.visible = _friends.visible


func _small(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"HintLabel"
	l.text = text
	return l


## The primary one is the amber accent button so the main action stands out.
func _button(id: StringName, text: String, on_press: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.name = String(id)
	b.text = text
	b.custom_minimum_size = BUTTON_SIZE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override(&"font_size", 22)
	if primary:
		b.theme_type_variation = &"AccentButton"
	b.pressed.connect(on_press)
	_buttons[id] = b
	return b


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

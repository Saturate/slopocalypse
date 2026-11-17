@tool
class_name UiTheme
extends Theme
## The project theme (`gui/theme/custom` points at ui_theme.tres, which is this script and
## nothing else). It builds itself from UiPalette when loaded, so colours and sizes live in
## one place. Being the project theme, it reaches every Control, including those under a
## CanvasLayer, which a theme set on the root window does not.
##
## Type variations: TitleLabel, HeadingLabel, HintLabel, HudLabel, HudNumber, TapeLabel,
## AccentButton.

## Loaded by path, not class name: as the project theme this script is parsed at startup,
## and on a fresh checkout that is before Godot has built its list of class names.
const Palette := preload("res://core/ui/ui_palette.gd")
const Plate := preload("res://core/ui/steel_plate.gd")

const HEADING_FONT := "res://core/ui/fonts/BlackOpsOne-Regular.ttf"
const BODY_FONT := "res://core/ui/fonts/BarlowCondensed-SemiBold.ttf"
const NUMBER_FONT := "res://core/ui/fonts/BarlowCondensed-Bold.ttf"
## Over the 3D world text needs an outline to read on both sky and asphalt.
const HUD_OUTLINE := 6
const BUTTON_SHADOW := Vector2(4, 4)


func _init() -> void:
	var heading: Font = load(HEADING_FONT)
	var body: Font = load(BODY_FONT)
	var number: Font = load(NUMBER_FONT)
	default_font = body
	default_font_size = Palette.BODY

	for type: StringName in [&"Label", &"Button", &"LineEdit", &"CheckBox", &"CheckButton", &"OptionButton", &"ItemList", &"Tree", &"RichTextLabel", &"PopupMenu", &"TooltipLabel"]:
		set_color(&"font_color", type, Palette.TEXT)
	set_color(&"default_color", &"RichTextLabel", Palette.TEXT)

	_plates()
	_buttons()
	_fields()

	_variation(&"TitleLabel", &"Label", heading, Palette.TITLE, Palette.ACCENT)
	_variation(&"HeadingLabel", &"Label", heading, Palette.HEADING, Palette.ACCENT)
	_variation(&"HintLabel", &"Label", body, Palette.HINT, Palette.DIM)
	_variation(&"TapeLabel", &"Label", body, Palette.HINT, Palette.INK)
	var tape := StyleBoxFlat.new()
	tape.bg_color = Palette.TAPE
	tape.content_margin_left = 8
	tape.content_margin_right = 8
	tape.content_margin_top = 1
	tape.content_margin_bottom = 1
	tape.shadow_color = Color(0, 0, 0, 0.35)
	tape.shadow_size = 1
	tape.shadow_offset = Vector2(1, 2)
	set_stylebox(&"normal", &"TapeLabel", tape)
	for hud: Array in [[&"HudLabel", body, Palette.HUD], [&"HudNumber", number, Palette.HUD_NUMBER]]:
		_variation(hud[0], &"Label", hud[1], hud[2], Palette.TEXT)
		set_constant(&"outline_size", hud[0], HUD_OUTLINE)
		set_color(&"font_outline_color", hud[0], Color(0, 0, 0, 0.85))
		set_color(&"font_shadow_color", hud[0], Color(0, 0, 0, 0.45))
		set_constant(&"shadow_offset_y", hud[0], 2)
		set_constant(&"shadow_offset_x", hud[0], 0)

	set_type_variation(&"AccentButton", &"Button")
	set_font(&"font", &"AccentButton", heading)
	for state: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
		set_color(state, &"AccentButton", Palette.INK)
	set_stylebox(&"normal", &"AccentButton", _plate(Palette.ACCENT, false, BUTTON_SHADOW, true))
	set_stylebox(&"hover", &"AccentButton", _plate(Palette.ACCENT.lightened(0.15), false, BUTTON_SHADOW, true))
	set_stylebox(&"pressed", &"AccentButton", _pressed(Palette.ACCENT.darkened(0.15), true))


func _variation(name: StringName, base: StringName, font: Font, size: int, colour: Color) -> void:
	set_type_variation(name, base)
	set_font(&"font", name, font)
	set_font_size(&"font_size", name, size)
	set_color(&"font_color", name, colour)


func _plate(fill: Color, rivets: bool, shadow: Vector2, stripe := false) -> Plate:
	var p := Plate.new()
	p.fill = fill
	p.rivets = rivets
	p.shadow = shadow
	p.stripe = stripe
	if stripe:
		p.content_margin_left = 28
	# Buttons are small and many; chipped edges on each would be noise.
	if not rivets:
		p.wear = false
	return p


## Pressed sits down into its own shadow.
func _pressed(fill: Color, stripe := false) -> Plate:
	var p := _plate(fill, false, Vector2.ZERO, stripe)
	p.bevel = 2.0
	p.content_margin_top = 14
	p.content_margin_bottom = 10
	return p


func _plates() -> void:
	var panel := _plate(Palette.STEEL, true, Vector2(7, 7))
	panel.content_margin_left = 24
	panel.content_margin_right = 24
	panel.content_margin_top = 20
	panel.content_margin_bottom = 20
	set_stylebox(&"panel", &"Panel", panel)
	set_stylebox(&"panel", &"PanelContainer", panel)
	var pop := _plate(Palette.STEEL, false, Vector2(4, 4))
	pop.wear = false
	set_stylebox(&"panel", &"PopupMenu", pop)
	set_stylebox(&"panel", &"TooltipPanel", pop)
	set_stylebox(&"panel", &"PopupPanel", pop)


func _buttons() -> void:
	for type: StringName in [&"Button", &"OptionButton", &"MenuButton"]:
		set_stylebox(&"normal", type, _plate(Palette.STEEL_RAISED, false, BUTTON_SHADOW))
		set_stylebox(&"hover", type, _plate(Palette.STEEL_RAISED.lightened(0.12), false, BUTTON_SHADOW))
		set_stylebox(&"pressed", type, _pressed(Palette.STEEL_SUNK))
		set_stylebox(&"hover_pressed", type, _pressed(Palette.STEEL_SUNK))
		var off := _plate(Palette.STEEL_SUNK, false, Vector2(2, 2))
		off.wear = false
		set_stylebox(&"disabled", type, off)
		var ring := Plate.new()
		ring.filled = false
		ring.outline = Palette.ACCENT
		set_stylebox(&"focus", type, ring)
		set_color(&"font_hover_color", type, Palette.ACCENT)
		set_color(&"font_focus_color", type, Palette.TEXT)
		set_color(&"font_pressed_color", type, Palette.ACCENT)
		set_color(&"font_disabled_color", type, Palette.DIM.darkened(0.3))


func _fields() -> void:
	var well := StyleBoxFlat.new()
	well.bg_color = Color(0, 0, 0, 0.35)
	# A light rim on every side so a field reads as something to type in, not a label.
	well.border_color = Color(1, 1, 1, 0.14)
	well.set_border_width_all(1)
	well.border_width_top = 2
	well.content_margin_left = 10
	well.content_margin_right = 10
	well.content_margin_top = 6
	well.content_margin_bottom = 6
	for type: StringName in [&"LineEdit", &"TextEdit", &"SpinBox", &"ItemList", &"Tree"]:
		set_stylebox(&"normal", type, well)
		set_stylebox(&"panel", type, well)
	var focus := well.duplicate() as StyleBoxFlat
	focus.border_color = Palette.ACCENT
	focus.set_border_width_all(2)
	set_stylebox(&"focus", &"LineEdit", focus)
	set_color(&"caret_color", &"LineEdit", Palette.ACCENT)
	set_color(&"selection_color", &"LineEdit", Color(Palette.ACCENT, 0.35))
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0, 0, 0, 0.45)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Palette.ACCENT
	bar_fill.border_color = Palette.ACCENT.lightened(0.3)
	bar_fill.border_width_top = 2
	set_stylebox(&"background", &"ProgressBar", bar_bg)
	set_stylebox(&"fill", &"ProgressBar", bar_fill)
	# Sliders: a sunk track with the filled part in the accent.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.45)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var filled := StyleBoxFlat.new()
	filled.bg_color = Palette.ACCENT
	filled.content_margin_top = 4
	filled.content_margin_bottom = 4
	set_stylebox(&"slider", &"HSlider", track)
	set_stylebox(&"grabber_area", &"HSlider", filled)
	set_stylebox(&"grabber_area_highlight", &"HSlider", filled)

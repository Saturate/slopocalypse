class_name ScreenFrame
extends Control
## A screen's frame: a dimmed backdrop, a centred steel panel with a title, a content column
## for the screen to fill, and a footer of key hints. The panel never grows past 90 % of
## the view; taller content scrolls inside it, so a screen fits at 720p.

## Share of the view the panel may take.
const MAX_SHARE := 0.9

## Fill this with the screen's controls.
var content: VBoxContainer
var title: Label

## The scroll area around `content`.
var scroll: ScrollContainer

var _panel: PanelContainer
var _footer: HBoxContainer


func _init(heading: String, width := 560.0) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = UiPalette.BACKDROP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 12)
	_panel.add_child(column)
	title = Label.new()
	title.theme_type_variation = &"HeadingLabel"
	title.text = heading
	column.add_child(title)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.x = width
	column.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override(&"separation", 8)
	scroll.add_child(content)
	var rule := HSeparator.new()
	column.add_child(rule)
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override(&"separation", 20)
	column.add_child(_footer)
	resized.connect(_fit)
	content.resized.connect(_fit)


func add_hint(action: StringName, what: String) -> KeyHint:
	var hint := KeyHint.new(action, what)
	_footer.add_child(hint)
	return hint


## The scroll area takes the content's height up to what keeps the panel inside the view.
func _fit() -> void:
	var view := get_viewport_rect().size if is_inside_tree() else size
	var chrome := _panel.get_combined_minimum_size().y - scroll.custom_minimum_size.y
	var room := maxf(view.y * MAX_SHARE - chrome, 80.0)
	scroll.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, room)


## Height the panel takes now, for tests.
func panel_height() -> float:
	return _panel.get_combined_minimum_size().y

class_name TraderPrompt
extends CanvasLayer
## Client only, local player: "F  Trade" while looking at the trader's stall.

var trader: Node
var player: Node3D

var _label: Label


func _ready() -> void:
	layer = 4
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_label.position += Vector2(-160, 88)
	_label.custom_minimum_size = Vector2(320, 24)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", 17)
	_label.add_theme_color_override(&"font_color", Color(0.95, 0.93, 0.85))
	_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override(&"outline_size", 6)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.text = "F   Trade"
	add_child(_label)


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		queue_free()
		return
	_label.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and bool(trader.call(&"at_stall", player))

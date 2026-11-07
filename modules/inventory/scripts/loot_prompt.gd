class_name LootPrompt
extends CanvasLayer
## Client only, local player: "E  Pick up <item>" under the crosshair while loot is in
## reach, using the same reach rule the server uses for the pickup.

var inventory: Node
var player: Node3D

var _label: Label


func _ready() -> void:
	layer = 4
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_label.position += Vector2(-120, 40)
	_label.custom_minimum_size = Vector2(240, 24)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", 17)
	_label.add_theme_color_override(&"font_color", Color(0.95, 0.93, 0.85))
	_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override(&"outline_size", 6)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		queue_free()
		return
	var loot: Node = inventory.call(&"loot_in_reach", player)
	_label.visible = loot != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if loot != null:
		var info: Dictionary = inventory.call(&"item_info", str(loot.get(&"item")))
		_label.text = "E   Pick up %s" % str(info.get("name", loot.get(&"item")))

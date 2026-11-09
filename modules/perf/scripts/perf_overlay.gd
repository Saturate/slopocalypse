extends CanvasLayer
## Client-only: the perf module's newest sample in a corner, toggled with `overlay_key` (F3).

## Set by the perf module before this enters the tree.
var perf: Node

var _label: Label
var _key: int = KEY_F3


func _ready() -> void:
	layer = 45
	_key = OS.find_keycode_from_string(str(perf.get(&"config").get("overlay_key", "F3")))
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	var backing := StyleBoxFlat.new()
	backing.bg_color = Color(0, 0, 0, 0.55)
	backing.set_content_margin_all(8)
	backing.set_corner_radius_all(4)
	panel.add_theme_stylebox_override(&"panel", backing)
	add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override(&"font_size", 13)
	_label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override(&"shadow_offset_x", 1)
	_label.add_theme_constant_override(&"shadow_offset_y", 1)
	panel.add_child(_label)
	visible = false
	perf.connect(&"sampled", _show)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == _key:
		visible = not visible
		_show(perf.call(&"latest"))


func _show(rec: Dictionary) -> void:
	if not visible or rec.is_empty():
		return
	var lines: Array[String] = [
		"%d fps   frame %.1f ms  (p95 %.1f, worst %.1f)" % [int(rec.get("fps", 0)), rec.get("frame_ms_mean", 0.0), rec.get("frame_ms_p95", 0.0), rec.get("frame_ms_max", 0.0)],
		"process %.1f ms   physics %.1f ms" % [rec.get("process_ms", 0.0), rec.get("physics_ms", 0.0)],
		"nodes %d   objects %d   memory %.0f MB   video %.0f MB" % [rec.get("nodes", 0), rec.get("objects", 0), rec.get("memory_mb", 0.0), rec.get("video_mb", 0.0)],
		"draw calls %d   primitives %d" % [rec.get("draw_calls", 0), rec.get("primitives", 0)],
	]
	if rec.has("net_out_bytes"):
		lines.append("net out %.1f KB/s   in %.1f KB/s   peers %d" % [rec["net_out_bytes"] / 1024.0, rec["net_in_bytes"] / 1024.0, rec.get("peers", 0)])
	var custom: Dictionary = rec.get("custom", {})
	for name: String in custom:
		lines.append("%s %s" % [name, custom[name]])
	_label.text = "\n".join(lines)

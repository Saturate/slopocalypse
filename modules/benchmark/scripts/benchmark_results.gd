class_name BenchmarkResults
extends CanvasLayer
## Client: the benchmark's numbers when the run ends: frame rate, 1 % low, worst frame,
## what drawing cost, and the worst hitches with what ran in them. Save report writes the
## file to send us; Back to menu leaves.

signal save_requested

const WIDTH := 600.0

var _frame: ScreenFrame
var _lines: VBoxContainer
var _status: Label
var _save: Button


func _ready() -> void:
	layer = UiLayers.MENU_SCREENS
	_frame = ScreenFrame.new("BENCHMARK", WIDTH)
	_frame.visible = false
	add_child(_frame)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override(&"separation", 6)
	_frame.content.add_child(_lines)
	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = WIDTH - 40.0
	_frame.content.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	_frame.content.add_child(row)
	_save = _button(row, &"Save", "Save report", func() -> void: save_requested.emit())
	_button(row, &"Leave", "Back to menu", func() -> void: Net.leave())
	_frame.add_hint(&"ui_cancel", "Back to menu")


func show_results(results: Dictionary, can_save: bool) -> void:
	for child in _lines.get_children():
		child.queue_free()
	_line("%.0f FPS" % results["fps_mean"], &"TitleLabel")
	# Plain words for players, so it outweighs the developer lines below.
	_line("on average, and %.0f fps in its slowest moments (the slowest 1%% of frames)" % results["fps_low_1pct"])
	_gap()
	_line("Frame time: %.1f ms average, %.1f ms for 95%% of frames, %.1f ms worst" % [results["frame_ms_mean"], results["frame_ms_p95"], results["frame_ms_worst"]])
	if results.has("draw_calls"):
		var gpu := "GPU %.1f ms" % float(results["gpu_ms"]) if results.has("gpu_ms") else "GPU not timed by %s" % str(results.get("driver", "this driver"))
		_line("Drawing: %d draw calls, %d objects; %s, render CPU %.1f ms a frame" % [int(results["draw_calls"]), int(results.get("objects_drawn", 0.0)), gpu, float(results.get("render_cpu_ms", 0.0))])
	if results.get("budget") is Dictionary:
		# The perf module's split (its PerfBudget), read by key so this module needs no other.
		var b: Dictionary = results["budget"]
		_line("Where a frame goes: scripts %.1f ms, physics %.1f, render %.1f, other %.1f" % [b.get("scripts_ms", 0.0), b.get("physics_ms", 0.0), b.get("render_ms", 0.0), b.get("other_ms", 0.0)], &"HintLabel")
	_line("%d frames over %d seconds" % [int(results["frames"]), int(results.get("seconds", 0.0))], &"HintLabel")
	var hitches: Array = results.get("hitches", [])
	if not hitches.is_empty():
		_gap()
		_line("Worst stutters, and what ran in them:", &"HintLabel")
	for h: Dictionary in hitches:
		_line("%.0f ms: %s" % [float(h["ms"]), _what_ran(h)])
	_status.text = "" if can_save else "Reports are off in this build, so there is nothing to save."
	_save.visible = can_save
	_frame.visible = true
	UiStack.push(self)


func show_saved(path: String) -> void:
	if path.is_empty():
		_status.text = "Could not save the report; the game log says why."
		return
	_status.text = "Saved %s\nin %s\nSend that file to us (Discord is fine)." % [path.get_file(), path.get_base_dir()]
	_save.visible = false
	OS.shell_show_in_file_manager(path)


func is_open() -> bool:
	return _frame.visible


func _input(event: InputEvent) -> void:
	if is_open() and UiStack.is_top(self) and UiStack.is_cancel(event):
		get_viewport().set_input_as_handled()
		Net.leave()


## The zones that ran in a hitch, slowest first, and any shader compiles.
static func _what_ran(h: Dictionary) -> String:
	var zones: Dictionary = h.get("zones", {})
	var names := zones.keys()
	names.sort_custom(func(a: Variant, b: Variant) -> bool: return float(zones[a]) > float(zones[b]))
	var parts: Array[String] = []
	for name: Variant in names.slice(0, 3):
		parts.append("%s %.1f ms" % [name, float(zones[name])])
	var compiles: Dictionary = h.get("compiles", {})
	if not compiles.is_empty():
		parts.append("shaders compiled")
	return ", ".join(parts) if not parts.is_empty() else "nothing measured in scripts"


func _gap() -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	_lines.add_child(gap)


func _line(text: String, variation: StringName = &"") -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH - 40.0
	if variation != &"":
		label.theme_type_variation = variation
	_lines.add_child(label)


func _button(row: HBoxContainer, id: StringName, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.name = String(id)
	b.text = text
	b.custom_minimum_size = Vector2(170, 40)
	b.pressed.connect(on_press)
	row.add_child(b)
	return b

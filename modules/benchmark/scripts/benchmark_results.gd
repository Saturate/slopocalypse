class_name BenchmarkResults
extends CanvasLayer
## Client: the benchmark's numbers when the run ends: frame rate, 1 % low, worst frame,
## what drawing cost, and the worst hitches with what ran in them. Save report writes the
## file to send us; Copy summary puts the headline numbers and the machine on the clipboard
## for a chat; Back to menu leaves.

signal save_requested

const WIDTH := 600.0

var _frame: ScreenFrame
var _lines: VBoxContainer
var _status: Label
var _save: Button
var _results: Dictionary = {}


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
	_button(row, &"Copy", "Copy summary", _copy_summary)
	_button(row, &"Leave", "Back to menu", func() -> void: Net.leave())
	_frame.add_hint(&"ui_cancel", "Back to menu")


func show_results(results: Dictionary, can_save: bool) -> void:
	_results = results
	for child in _lines.get_children():
		child.queue_free()
	_line("%.0f FPS" % results["fps_mean"], &"TitleLabel")
	# Plain words for players, so it outweighs the developer lines below.
	_line("on average, and %.0f fps in its slowest moments (the slowest 1%% of frames)" % results["fps_low_1pct"])
	_gap()
	_line("Frame time: %.1f ms average, %.1f ms for 95%% of frames, %.1f ms worst" % [results["frame_ms_mean"], results["frame_ms_p95"], results["frame_ms_worst"]])
	if results.has("draw_calls"):
		_line("Drawing: %d draw calls, %d objects; GPU %.1f ms, render CPU %.1f ms a frame" % [int(results["draw_calls"]), int(results.get("objects_drawn", 0.0)), float(results.get("gpu_ms", 0.0)), float(results.get("render_cpu_ms", 0.0))])
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


## The short summary of this run and machine (BenchmarkStats.summary_text) onto the clipboard.
func _copy_summary() -> void:
	DisplayServer.clipboard_set(BenchmarkStats.summary_text(_results, machine(get_viewport())))
	_status.text = "Copied. Paste it wherever you share results."


## What the short summary says about the machine: no names, keys or paths.
static func machine(viewport: Viewport) -> Dictionary:
	var size := viewport.get_visible_rect().size if viewport != null else Vector2.ZERO
	return {
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"gpu": RenderingServer.get_video_adapter_name(),
		"renderer": "%s (%s)" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name()],
		"cpu": OS.get_processor_name(),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"resolution": "%dx%d" % [int(size.x), int(size.y)] if size != Vector2.ZERO else "",
	}


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

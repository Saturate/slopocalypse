extends Node
## The benchmark (#377): "Benchmark" in the main menu starts a fixed run, the same on every
## machine. Solo in the city (`args` in the data): the city bot walks the avenues while squads
## land in front of the player and die one by one, the heaviest place to draw plus spawns and
## deaths. After `warmup_seconds` it times every frame for `measure_seconds`, then shows the
## numbers and the worst hitches, and "Save report" writes the bug report's file (#384) with
## them in it. `--benchmark-out=PATH` writes the results there as JSON and quits instead
## (tools/bench.ts benchmark).

const CONFIG := "res://modules/benchmark/data/benchmark.json"
const REQUIRED := {"warmup_seconds": TYPE_FLOAT, "measure_seconds": TYPE_FLOAT, "top_hitches": TYPE_FLOAT, "args": TYPE_ARRAY}
const FLAG := "--benchmark"
const OUT_PREFIX := "--benchmark-out="

var config: Dictionary = {}
## True in a benchmark session.
var active := false
## The results once the run is over (empty before).
var results: Dictionary = {}
## Where the results go as JSON (`--benchmark-out=`); the game then quits.
var out_path := ""

var _clock := 0.0
var _last_usec := 0
var _frames := PackedFloat32Array()
## The perf module's samples taken while measuring.
var _samples: Array[Dictionary] = []
var _status: Label
var _screen: BenchmarkResults
## Quit once the results are written (a tool run), not a test calling `finish`.
var _quit_when_done := false
var _vsync_before := DisplayServer.VSYNC_ENABLED
var _max_fps_before := 0


## What a session needs to be the benchmark; the menu adds these.
static func session_args() -> PackedStringArray:
	var out := PackedStringArray([FLAG])
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if data is Dictionary and (data as Dictionary).get("args") is Array:
		for arg: Variant in data["args"]:
			out.append(str(arg))
	return out


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not (data is Dictionary and Data.require(CONFIG, data, REQUIRED)):
		return
	config = data
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(OUT_PREFIX):
			out_path = arg.trim_prefix(OUT_PREFIX)
			_quit_when_done = true
	active = Net.session_args().has(FLAG) and DisplayServer.get_name() != "headless"
	if not active:
		set_process(false)
		return
	# Uncapped, so a fast machine shows its frame rate rather than its monitor's.
	_vsync_before = DisplayServer.window_get_vsync_mode()
	_max_fps_before = Engine.max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_status = Label.new()
	_status.name = "BenchmarkStatus"
	_status.theme_type_variation = &"HintLabel"
	_status.position = Vector2(16, 16)
	var layer := CanvasLayer.new()
	layer.layer = UiLayers.MENU_SCREENS
	layer.add_child(_status)
	add_child(layer)
	_screen = BenchmarkResults.new()
	_screen.name = "BenchmarkResults"
	_screen.save_requested.connect(_save)
	add_child(_screen)
	var perf := get_tree().get_first_node_in_group(&"perf_api")
	if perf != null:
		perf.connect(&"sampled", _on_sampled)


func _exit_tree() -> void:
	if active:
		DisplayServer.window_set_vsync_mode(_vsync_before)
		Engine.max_fps = _max_fps_before


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_usec) / 1000.0 if _last_usec > 0 else delta * 1000.0
	_last_usec = now
	# The clock starts once connected: loading the game is not part of the run.
	if not Net.is_session_connected() or not results.is_empty():
		return
	_clock += delta
	var warmup := float(config["warmup_seconds"])
	var measure := float(config["measure_seconds"])
	if _clock < warmup:
		_status.text = "Benchmark: warming up %d s" % ceili(warmup - _clock)
		return
	if _clock < warmup + measure:
		_frames.append(ms)
		_status.text = "Benchmark: measuring %d s" % ceili(warmup + measure - _clock)
		return
	finish()


func _on_sampled(record: Dictionary) -> void:
	var warmup := float(config["warmup_seconds"])
	if _clock < warmup or not results.is_empty():
		return
	_samples.append(record)


## Ends the run with the frames timed so far: results, then the file or the screen.
func finish() -> void:
	results = BenchmarkStats.summarise(_frames)
	results.merge(BenchmarkStats.average_samples(_samples))
	results["seconds"] = float(config["measure_seconds"])
	results["hitches"] = _hitches()
	if _status != null:
		_status.text = ""
	if not out_path.is_empty():
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			Log.error(&"benchmark", "cannot write %s: %s" % [out_path, error_string(FileAccess.get_open_error())])
		else:
			f.store_string(JSON.stringify(results, "  "))
			f.close()
		if _quit_when_done:
			get_tree().quit(0 if f != null else 1)
		return
	if _screen != null:
		_screen.show_results(results, get_tree().get_first_node_in_group(&"report_api") != null)


## The worst hitches of the measured part of the run, from the perf log's spike lines. The
## perf clock starts before this one, so the window is the last `measure_seconds` of it.
func _hitches() -> Array[Dictionary]:
	var perf := get_tree().get_first_node_in_group(&"perf_api")
	if perf == null:
		return []
	var text := FileAccess.get_file_as_string(str(perf.call(&"log_path")))
	var uptime := float((perf.call(&"latest") as Dictionary).get("t", _clock))
	var measure := float(config["measure_seconds"])
	return BenchmarkStats.worst_hitches(text, uptime - measure, uptime + 1.0, int(config["top_hitches"]))


func _save() -> void:
	var report := get_tree().get_first_node_in_group(&"report_api")
	if report == null:
		return
	var shot := PackedByteArray()
	var image := get_viewport().get_texture().get_image()
	if image != null:
		shot = image.save_png_to_buffer()
	_screen.show_saved(str(report.call(&"save_report", "benchmark", "", shot, {"benchmark": results})))

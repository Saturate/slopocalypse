extends Node
## Performance log. Every `sample_seconds` this process (client or server) writes one NDJSON
## line to user://perf/<role>-<time>.ndjson: frame times (mean, p95, worst), fps, process
## and physics step time, node and object counts, memory, draw calls, network bytes, and every
## Godot custom monitor that other modules register (`Performance.add_custom_monitor`), so
## this module never needs to know about them. A frame slower than `spike_ms` gets a line of
## its own, at most one a second, once the warm-up is over. Clients get an overlay (F3).
##
## Other code reads the newest sample through the `perf_api` group: `latest()`, `sampled`.
## `-- --perf-log=PATH` writes to that file instead, and `--no-vsync` turns vsync off
## (tools/bench.ts uses both).

const CONFIG := "res://modules/perf/data/perf.json"
const REQUIRED := {"sample_seconds": TYPE_FLOAT, "spike_ms": TYPE_FLOAT, "warmup_seconds": TYPE_FLOAT, "keep_files": TYPE_FLOAT, "overlay_key": TYPE_STRING}
## Spike lines are rate-limited to one per this many seconds.
const SPIKE_GAP_SECONDS := 1.0

signal sampled(record: Dictionary)

## Where logs go; tests point this elsewhere before the module enters the tree.
var log_dir := "user://perf"
var config: Dictionary = {}

var _sampler := PerfSampler.new()
var _file: FileAccess
var _path := ""
var _since_sample := 0.0
var _uptime := 0.0
var _last_spike := -INF
var _latest: Dictionary = {}
## Wall-clock time of the last frame: `delta` is clamped, scaled and fixed under --fixed-fps,
## so it is not what the frame really took.
var _last_usec := 0


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not Data.require(CONFIG, data, REQUIRED):
		return
	config = data
	add_to_group(&"perf_api")
	_open_log()
	if DisplayServer.get_name() != "headless":
		# The GPU's and the CPU's own time for drawing each frame: tells whether a slow frame
		# waits on the graphics card or on the processor.
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		# Benchmarks measure the game, not the monitor's refresh rate.
		if OS.get_cmdline_user_args().has("--no-vsync"):
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		var overlay: Node = (load("res://modules/perf/scripts/perf_overlay.gd") as GDScript).new()
		overlay.name = "Overlay"
		overlay.set(&"perf", self)
		add_child(overlay)


func _exit_tree() -> void:
	if _file != null:
		_file.close()
		_file = null


## The newest sample (empty until the first one).
func latest() -> Dictionary:
	return _latest


## The file this process logs to.
func log_path() -> String:
	return _path


func _process(delta: float) -> void:
	if config.is_empty():
		return
	var now := Time.get_ticks_usec()
	var ms := (now - _last_usec) / 1000.0 if _last_usec > 0 else delta * 1000.0
	_last_usec = now
	_uptime += delta
	_sampler.add_frame(ms)
	if ms > float(config["spike_ms"]) and _uptime > float(config["warmup_seconds"]) and _uptime - _last_spike >= SPIKE_GAP_SECONDS:
		_last_spike = _uptime
		_write({"t": snappedf(_uptime, 0.001), "spike_ms": snappedf(ms, 0.01), "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))})
	_since_sample += delta
	if _since_sample >= float(config["sample_seconds"]):
		_since_sample = 0.0
		_latest = _sample()
		_write(_latest)
		sampled.emit(_latest)


func _role() -> String:
	if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return "local"
	return "server" if multiplayer.is_server() else "client"


func _sample() -> Dictionary:
	var rec := {"t": snappedf(_uptime, 0.001), "role": _role()}
	rec.merge(_sampler.take())
	for key: String in ["frame_ms_mean", "frame_ms_p95", "frame_ms_max"]:
		rec[key] = snappedf(float(rec[key]), 0.01)
	rec["fps"] = Performance.get_monitor(Performance.TIME_FPS)
	rec["process_ms"] = snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01)
	rec["physics_ms"] = snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01)
	rec["nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	rec["objects"] = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	rec["orphans"] = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	rec["memory_mb"] = snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1)
	if DisplayServer.get_name() != "headless":
		rec["draw_calls"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		rec["primitives"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		rec["video_mb"] = snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1)
		var vp := get_viewport().get_viewport_rid()
		rec["gpu_ms"] = snappedf(RenderingServer.viewport_get_measured_render_time_gpu(vp), 0.01)
		rec["render_cpu_ms"] = snappedf(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(), 0.01)
	var peer: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer if multiplayer.has_multiplayer_peer() else null
	if peer != null and peer.host != null:
		# pop_statistic resets the counter, so these are bytes since the last sample.
		rec["net_out_bytes"] = int(peer.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))
		rec["net_in_bytes"] = int(peer.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA))
		rec["peers"] = multiplayer.get_peers().size()
	var custom := {}
	for name: StringName in Performance.get_custom_monitor_names():
		custom[String(name)] = Performance.get_custom_monitor(name)
	if not custom.is_empty():
		rec["custom"] = custom
	return rec


func _open_log() -> void:
	# tools/bench.ts says exactly where to write, so it knows which file to read.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--perf-log="):
			_path = arg.trim_prefix("--perf-log=")
			DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
			_file = FileAccess.open(_path, FileAccess.WRITE)
			if _file == null:
				Log.warn(&"perf", "cannot write %s: %s" % [_path, error_string(FileAccess.get_open_error())])
			return
	DirAccess.make_dir_recursive_absolute(log_dir)
	var names: Array[String] = []
	names.assign(DirAccess.get_files_at(log_dir))
	for old in PerfSampler.to_prune(names, maxi(int(config["keep_files"]) - 1, 0)):
		DirAccess.remove_absolute(log_dir.path_join(old))
	var stamp := Time.get_datetime_string_from_system(false, false).replace("-", "").replace(":", "").replace("T", "-")
	# Several processes can start in the same second (solo starts a server): add the pid.
	_path = log_dir.path_join("%s-%s-%d.ndjson" % [_role_at_start(), stamp, OS.get_process_id()])
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		Log.warn(&"perf", "cannot write %s: %s" % [_path, error_string(FileAccess.get_open_error())])
	else:
		Log.info(&"perf", "logging to %s" % ProjectSettings.globalize_path(_path))


## The session may not be up yet when the log opens; name the file by what this process is.
func _role_at_start() -> String:
	if DisplayServer.get_name() == "headless" and not Net.has_local_player():
		return "server"
	return "client"


func _write(rec: Dictionary) -> void:
	if _file == null:
		return
	_file.store_line(JSON.stringify(rec))
	# A crash should not lose the last seconds.
	_file.flush()

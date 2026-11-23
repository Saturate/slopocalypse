extends Node
## Performance log. Every `sample_seconds` this process (client or server) writes one NDJSON
## line to user://perf/<role>-<time>.ndjson: frame times (mean, p95, worst), fps, process
## and physics step time, node and object counts, memory, draw calls, network bytes, and every
## Godot custom monitor that other modules register (`Performance.add_custom_monitor`), so
## this module never needs to know about them. A frame slower than `spike_ms` gets a line of
## its own once the warm-up is over, with any shader compiles: the first after a quiet second
## at once, then the slowest of the rest each second, so lines can trail samples by a second.
## Clients get an overlay (F3).
##
## Each sample also splits the mean frame into a budget (PerfBudget: scripts, physics, render,
## other; GPU beside it), sums zones by module, and on a client counts what the visible pass
## and the shadow passes drew. Drivers that cannot time the GPU (Metal) leave `gpu_ms` out.
##
## Other code reads the newest sample through the `perf_api` group: `latest()`, `sampled`.
## `-- --perf-log=PATH` writes to that file instead, and `--uncapped` turns off vsync and the
## idle sleep between frames, so frame times are work, not waiting (tools/bench.ts uses both).

const CONFIG := "res://modules/perf/data/perf.json"
const REQUIRED := {"sample_seconds": TYPE_FLOAT, "spike_ms": TYPE_FLOAT, "warmup_seconds": TYPE_FLOAT, "keep_files": TYPE_FLOAT, "overlay_key": TYPE_STRING}
## Spike lines are rate-limited to one per this many seconds.
const SPIKE_GAP_SECONDS := 1.0
## Zones listed on a spike line, most expensive first.
const SPIKE_ZONES := 5
## Godot 4.7's Metal driver has no timestamp queries (its query pool returns zeros), so the
## GPU time it reports is always 0, not a measurement.
const GPU_UNTIMED_DRIVERS: Array[String] = ["metal"]
## What viewport_get_render_info counts, under the names the log uses.
const RENDER_INFO := {
	"objects": RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME,
	"primitives": RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME,
	"draw_calls": RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME,
}
const PIPELINE_MONITORS := {
	"canvas": Performance.PIPELINE_COMPILATIONS_CANVAS,
	"mesh": Performance.PIPELINE_COMPILATIONS_MESH,
	"surface": Performance.PIPELINE_COMPILATIONS_SURFACE,
	"draw": Performance.PIPELINE_COMPILATIONS_DRAW,
	"specialization": Performance.PIPELINE_COMPILATIONS_SPECIALIZATION,
}

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
## Running pipeline compile totals by kind, as of last frame.
var _compiled: Dictionary[String, int] = {}
var _latest: Dictionary = {}
## Wall-clock time of the last frame: `delta` is clamped, scaled and fixed under --fixed-fps,
## so it is not what the frame really took.
var _last_usec := 0
## Physics tick split: when the nodes' physics began this tick, and the totals this sample.
var _tick_began := 0
var _nodes_usec := 0
var _ticks := 0
## Frames since the last sample: synchronizers send their every-frame properties once each.
var _frames := 0
## Frame budget, microseconds this sample (see PerfBudget). `Prof.covered_usec()` read at
## each mark takes the zones' time out of the physics parts, so nothing counts twice.
var _scripts_usec := 0
var _physics_usec := 0
var _render_usec := 0
var _covered_last_frame := 0
var _covered_at_tick := 0
## When the last tick's nodes finished (0: not in the engine's part of a tick).
var _nodes_ended := 0
var _covered_at_nodes_end := 0
var _draw_began := 0


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not Data.require(CONFIG, data, REQUIRED):
		return
	config = data.duplicate()
	# Benchmarks look for smaller hitches than everyday logging does.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--perf-spike-ms="):
			config["spike_ms"] = float(arg.trim_prefix("--perf-spike-ms="))
	add_to_group(&"perf_api")
	_open_log()
	if OS.get_cmdline_user_args().has("--uncapped"):
		# Benchmarks measure the game, not the monitor's refresh rate or the sleep a headless
		# server takes between frames.
		OS.low_processor_usage_mode = false
		# A headless process sleeps this long every frame (no window can draw) regardless.
		OS.low_processor_usage_mode_sleep_usec = 0
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# Godot emits physics_frame just before nodes run their physics; a probe with the highest
	# priority runs last. The time between is all nodes' _physics_process; the rest of the
	# physics tick is the engine (the physics server's step, sync and callbacks).
	get_tree().physics_frame.connect(_on_physics_frame)
	get_tree().process_frame.connect(_on_process_frame)
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	_covered_last_frame = Prof.covered_usec()
	var probe := Node.new()
	probe.name = "TickProbe"
	probe.process_physics_priority = 2147483647
	probe.set_script(load("res://modules/perf/scripts/tick_probe.gd"))
	probe.set(&"perf", self)
	add_child(probe)
	if DisplayServer.get_name() != "headless":
		# The GPU's and the CPU's own time for drawing each frame: tells whether a slow frame
		# waits on the graphics card or on the processor.
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		var overlay: Node = (load("res://modules/perf/scripts/perf_overlay.gd") as GDScript).new()
		overlay.name = "Overlay"
		overlay.set(&"perf", self)
		add_child(overlay)


func _exit_tree() -> void:
	for pair: Array in [[RenderingServer.frame_pre_draw, _on_pre_draw], [RenderingServer.frame_post_draw, _on_post_draw]]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])
	if _file != null:
		# A bench run often ends right after the hitch it is about.
		var spike := _sampler.take_spike()
		if not spike.is_empty():
			_write(spike)
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
	_frames += 1
	var covered := Prof.covered_usec()
	var frame_scripts := covered - _covered_last_frame
	_covered_last_frame = covered
	_scripts_usec += frame_scripts
	# The zones that ran since this point last frame: what the frame just measured was doing.
	var frame_zones := Prof.take_frame(SPIKE_ZONES)
	var compiles := _pipeline_compiles()
	if ms > float(config["spike_ms"]) and _uptime > float(config["warmup_seconds"]):
		var line := {"t": snappedf(_uptime, 0.001), "spike_ms": snappedf(ms, 0.01), "scripts_ms": snappedf(frame_scripts / 1000.0, 0.01), "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "zones": frame_zones}
		if not compiles.is_empty():
			line["compiles"] = compiles
		_sampler.offer_spike(line)
	if _uptime - _last_spike >= SPIKE_GAP_SECONDS:
		var spike := _sampler.take_spike()
		if not spike.is_empty():
			_last_spike = _uptime
			_write(spike)
	_since_sample += delta
	if _since_sample >= float(config["sample_seconds"]):
		_since_sample = 0.0
		_latest = _sample()
		_write(_latest)
		sampled.emit(_latest)


## Shader pipelines the renderer compiled since last frame, by kind, leaving out kinds with
## none. A pipeline compiled while drawing stalls that frame and runs in no script zone, so
## it is the usual reason a spike line shows nothing expensive.
func _pipeline_compiles() -> Dictionary:
	var out := {}
	for kind: String in PIPELINE_MONITORS:
		var total := int(Performance.get_monitor(PIPELINE_MONITORS[kind]))
		var grew := total - int(_compiled.get(kind, total))
		_compiled[kind] = total
		if grew > 0:
			out[kind] = grew
	return out


## Called by the probe at the end of each physics tick's node processing.
func physics_nodes_done() -> void:
	if _tick_began > 0:
		var now := Time.get_ticks_usec()
		var covered := Prof.covered_usec()
		_nodes_usec += now - _tick_began
		_physics_usec += maxi(now - _tick_began - (covered - _covered_at_tick), 0)
		_ticks += 1
		_nodes_ended = now
		_covered_at_nodes_end = covered


## Godot emits physics_frame just before a tick's nodes run.
func _on_physics_frame() -> void:
	_end_engine_step()
	_tick_began = Time.get_ticks_usec()
	_covered_at_tick = Prof.covered_usec()


func _on_process_frame() -> void:
	_end_engine_step()


## From the end of a tick's nodes to the next tick or the frame's _process: deferred calls,
## physics-mode timers and tweens, the physics server's step, and between two ticks of one
## frame the next tick's sync and body callbacks (less any zones those ran). After the last
## tick it also holds the network receive: SceneTree polls the multiplayer API (RPCs,
## synchronizer updates, spawns) just before process_frame, with nothing to mark between.
## The first tick's sync and callbacks come before any mark and land in "other".
func _end_engine_step() -> void:
	if _nodes_ended == 0:
		return
	var spent := Time.get_ticks_usec() - _nodes_ended
	_physics_usec += maxi(spent - (Prof.covered_usec() - _covered_at_nodes_end), 0)
	_nodes_ended = 0


func _on_pre_draw() -> void:
	_draw_began = Time.get_ticks_usec()


func _on_post_draw() -> void:
	if _draw_began > 0:
		_render_usec += Time.get_ticks_usec() - _draw_began
		_draw_began = 0


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
	# Godot's own process and physics timings are the slowest moment in roughly the last
	# second, so they show spikes, not typical cost.
	rec["process_peak_ms"] = snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01)
	rec["physics_peak_ms"] = snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01)
	if _ticks > 0:
		rec["physics_nodes_ms"] = snappedf(_nodes_usec / 1000.0 / _ticks, 0.01)
		rec["physics_ticks"] = _ticks
	_nodes_usec = 0
	_ticks = 0
	rec["budget"] = PerfBudget.split(float(rec["frame_ms_mean"]), int(rec["frames"]), _scripts_usec, _physics_usec, _render_usec)
	_scripts_usec = 0
	_physics_usec = 0
	_render_usec = 0
	rec["nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	rec["objects"] = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	rec["orphans"] = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	# What the physics engine is juggling: bodies awake, contact pairs, islands it solves.
	rec["physics_active"] = int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	rec["physics_pairs"] = int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
	rec["physics_islands"] = int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT))
	rec["memory_mb"] = snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1)
	if DisplayServer.get_name() != "headless":
		rec["draw_calls"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		# Mesh instances drawn after culling, summed over every pass (shadow maps included):
		# with the draw calls, how many things the frame is made of, not just how heavy.
		rec["objects_drawn"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		rec["primitives"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		rec["video_mb"] = snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1)
		var vp := get_viewport().get_viewport_rid()
		var driver := RenderingServer.get_current_rendering_driver_name()
		rec["driver"] = driver
		if not GPU_UNTIMED_DRIVERS.has(driver):
			rec["gpu_ms"] = snappedf(RenderingServer.viewport_get_measured_render_time_gpu(vp), 0.01)
		# The camera's own pass against the shadow maps': which one the objects cost.
		for pass_name: String in ["visible", "shadow"]:
			var kind := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE if pass_name == "visible" else RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW
			var counts := {}
			for key: String in RENDER_INFO:
				counts[key] = RenderingServer.viewport_get_render_info(vp, kind, RENDER_INFO[key])
			rec[pass_name] = counts
		rec["render_cpu_ms"] = snappedf(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(), 0.01)
	var peer: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer if multiplayer.has_multiplayer_peer() else null
	if peer != null and peer.host != null:
		# pop_statistic resets the counter, so these are bytes since the last sample.
		rec["net_out_bytes"] = int(peer.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))
		rec["net_in_bytes"] = int(peer.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA))
		rec["peers"] = multiplayer.get_peers().size()
		if multiplayer.is_server() and rec["peers"] > 0:
			rec["net"] = _net_breakdown(int(rec["net_out_bytes"]), int(rec["peers"]))
	_frames = 0
	if not rec.has("net"):
		# Nothing to report them against (a client, or no one connected): start again.
		NetStats.take()
	# Our own code, by zone (see core/prof.gd): milliseconds spent in this sample window.
	var zones := Prof.take()
	if not zones.is_empty():
		rec["zones"] = zones
		rec["modules"] = PerfBudget.by_module(zones, int(rec["frames"]))
	var custom := {}
	for name: StringName in Performance.get_custom_monitor_names():
		custom[String(name)] = Performance.get_custom_monitor(name)
	if not custom.is_empty():
		rec["custom"] = custom
	return rec


## Server: what it sent this sample, per second. `out_per_peer` is ENet's exact total over the
## peers; `sources` are estimates (see NetStats): every synchronizer's every-frame properties
## by scene, broadcast events by topic, shot replays; `other` is what they leave unexplained
## (packet headers, acks, on-change properties, RPCs nobody counts yet).
func _net_breakdown(out_bytes: int, peers: int) -> Dictionary:
	var seconds := maxf(float(config["sample_seconds"]), 0.001)
	var sources := NetStats.take()
	# Once a sample, on the server only: a walk of the tree costs about a millisecond.
	for node: Node in get_tree().root.find_children("*", "MultiplayerSynchronizer", true, false):
		var sync := node as MultiplayerSynchronizer
		if sync == null or sync.replication_config == null:
			continue
		var root := sync.get_node_or_null(sync.root_path)
		if root == null:
			continue
		var cfg := sync.replication_config
		var size := 0
		for prop: NodePath in cfg.get_properties():
			if cfg.property_get_replication_mode(prop) != SceneReplicationConfig.REPLICATION_MODE_ALWAYS:
				continue
			var holder := root.get_node_or_null(NodePath(String(prop.get_concatenated_names())))
			if holder != null:
				size += NetStats.size_of(holder.get_indexed(NodePath(String(prop.get_concatenated_subnames()))))
		var key := "sync/" + (root.scene_file_path.get_file().get_basename() if not root.scene_file_path.is_empty() else String(root.name))
		# Once a frame, or once per `replication_interval` when that is longer.
		var sends := _frames if sync.replication_interval <= 0.0 else mini(_frames, roundi(seconds / sync.replication_interval))
		# Only the peers it is shown to (see NetRelevance).
		var shown := peers
		if not sync.public_visibility:
			shown = 0
			for peer in multiplayer.get_peers():
				if sync.get_visibility_for(peer):
					shown += 1
		sources[key] = int(sources.get(key, 0)) + size * sends * shown
	var counted := 0
	var per_second := {}
	for key: String in sources:
		counted += int(sources[key])
		per_second[key] = roundi(int(sources[key]) / seconds)
	per_second["other"] = roundi(maxi(out_bytes - counted, 0) / seconds)
	return {"out_per_peer": roundi(out_bytes / seconds / peers), "sources": per_second}


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

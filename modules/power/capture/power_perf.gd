extends Node3D
## Capture setup for cost: the default map from high over its substation, looking out over
## the towns' high-voltage lines and the pole lines round the city. Every tower and wire is
## put up at once, then hidden and shown in turn, so the land and scenery behind are the same
## in each window. Prints (`power: ...` in the output) what building them cost, and per
## window the draw calls, primitives and objects in a frame, the measured render times and
## the wall time a frame took (run it directly, without movie pacing, for that to mean
## anything), averaged over the window.

const WORLD := "res://modules/world/scenes/world.tscn"
const POWER := "res://modules/power/power_module.gd"
const WIRES := "res://modules/wires/wires_module.gd"
const SITES := "res://modules/sites/sites_module.gd"
## Metres over the substation the camera stands, and how far back from it (away from the
## lines' middle).
const HIGH := 45.0
const BACK := 120.0
const SETTLE := 120
const MEASURE := 60
## Shown or hidden in each window, in turn.
const WINDOWS: Array[bool] = [false, true, false, true, false, true]

var _world: Node
var _terrain: VoxelWorld
var _camera := Camera3D.new()
var _frame := 0
var _sums := {}
var _window := -1
var _last_usec := 0
var _wires: Node
var _power: Node


func _ready() -> void:
	_world = await VoxelWorld.add_and_wait(self, WORLD)
	_terrain = _world.get_node("Terrain")
	var sites: Node = (load(SITES) as GDScript).new()
	add_child(sites)
	_wires = (load(WIRES) as GDScript).new()
	add_child(_wires)
	_power = (load(POWER) as GDScript).new()
	add_child(_power)
	var started := Time.get_ticks_usec()
	EventBus.publish(&"world.ready", {"spawn": VoxelWorld.spawn_of(_world)})
	_power.call(&"build_all")
	_wires.call(&"flush")
	print("power: %d towers, %d wire spans in %d chunks, %d shared meshes, built at once in %.0f ms" % [(_power.get(&"towers") as Array).size(),
		_wires.call(&"span_count"), (_wires.call(&"chunk_nodes") as Array).size(), VoxPiece.shared_mesh_count(), float(Time.get_ticks_usec() - started) / 1000.0])
	sites.call(&"build_all")
	var lines := _terrain.map_power_lines()
	var middle := Vector3.ZERO
	var count := 0
	var start := Vector3.ZERO
	for line: Dictionary in lines:
		for p: Vector3 in line["points"]:
			middle += p
			count += 1
		if line["from"] == "substation":
			start = (line["points"] as Array)[0]
	middle /= maxf(count, 1.0)
	var away := Vector3(start.x - middle.x, 0.0, start.z - middle.z).normalized()
	_camera.fov = 75.0
	_camera.far = 2500.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(_terrain.make_viewer())
	_camera.global_position = start + away * BACK + Vector3.UP * HIGH
	_camera.look_at(middle + Vector3.UP * 10.0)
	var focus: Array[Vector3] = [_camera.global_position]
	for line: Dictionary in lines:
		for p: Vector3 in line["points"]:
			focus.append(p)
	_terrain.update_around(focus, INF)
	(_world.get_node("Scenery") as SceneryScatter).update_around(focus, INF)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	# The wall time a frame takes is the cost, not the display's refresh.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _process(_delta: float) -> void:
	if _power == null:
		return
	var now_usec := Time.get_ticks_usec()
	var wall := float(now_usec - _last_usec) / 1000.0
	_last_usec = now_usec
	_frame += 1
	var window := _frame / (SETTLE + MEASURE)
	if window >= WINDOWS.size():
		if window == WINDOWS.size() and _frame % (SETTLE + MEASURE) == 0:
			_report()
		return
	if window != _window:
		if _window >= 0:
			_report()
		_window = window
		_sums = {}
		for chunk: Node3D in _wires.call(&"chunk_nodes"):
			chunk.visible = WINDOWS[window]
		for piece: Node3D in _power.get(&"towers"):
			piece.visible = WINDOWS[window]
	if _frame % (SETTLE + MEASURE) >= SETTLE:
		_add(wall)


func _report() -> void:
	var out := {}
	for key: String in _sums:
		out[key] = float(_sums[key]) / MEASURE
	print("power: %s: %d draws, %d primitives, %d objects, render cpu %.2f ms, gpu %.2f ms, frame %.2f ms" % ["shown" if WINDOWS[_window] else "hidden",
		roundi(out.get("draws", 0.0)), roundi(out.get("primitives", 0.0)), roundi(out.get("objects", 0.0)), out.get("cpu_ms", 0.0), out.get("gpu_ms", 0.0), out.get("wall_ms", 0.0)])


func _add(wall: float) -> void:
	var rid := get_viewport().get_viewport_rid()
	var now := {
		"draws": float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)),
		"cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu(),
		"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(rid),
		"wall_ms": wall,
	}
	for key: String in now:
		_sums[key] = float(_sums.get(key, 0.0)) + float(now[key])

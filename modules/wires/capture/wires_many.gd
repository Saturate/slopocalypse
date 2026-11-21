extends Node3D
## Capture setup for cost: rows of power lines and fences across the ground out from the
## camp, 1200 spans in all, seen from above. Prints (`wires: ...` in the output) the cost of
## building them all at once on this thread, then of building them the way the game does
## (worker threads, a budget a frame): the slowest unit of work, the most wire time in one
## frame, and the draw calls and primitives they add to a frame.

const WORLD := "res://modules/world/scenes/world.tscn"
const WIRES := "res://modules/wires/wires_module.gd"
const BEFORE := 30
const BUILD := 32
const SETTLE := 20
## Twenty pole lines of ten 40 m spans, three wires each; ten fences of twenty 3 m panels,
## three strands each.
const LINES := 20
const POLES := 11
const FENCES := 10
const PANELS := 20

var _world: Node
var _wires: Node
var _camera := Camera3D.new()
var _ticks := 0
var _before := {}
var _sets: Dictionary[String, Array] = {}
var _phase := ""
var _phase_frames := 0
var _idle_ticks := 0


func _ready() -> void:
	_world = await VoxelWorld.add_and_wait(self, WORLD)
	add_child(_camera)
	_camera.current = true
	_camera.fov = 65.0
	_camera.far = 1000.0
	_camera.global_position = VoxelWorld.spawn_of(_world, Vector3(0, 40, 60))
	_camera.look_at(VoxelWorld.spawn_of(_world, Vector3(0, 0, -150)))
	_make_sets()


func _process(_delta: float) -> void:
	if _world == null:
		return
	_ticks += 1
	if _ticks == BEFORE:
		_before = _frame_info()
	elif _ticks == BUILD:
		_at_once()
		_wires = (load(WIRES) as GDScript).new()
		add_child(_wires)
		_phase = "all"
		for owner: String in _sets:
			_wires.call(&"set_spans", owner, _sets[owner])
	elif _phase != "":
		_phase_frames += 1
		if _wires.is_processing():
			return
		_idle_ticks += 1
		if _idle_ticks < SETTLE:
			return
		if _phase == "all":
			var after := _frame_info()
			print("wires: threaded, all %d spans: built over %d frames; slowest unit %.2f ms on a worker, %.2f ms here; most wire time in a frame %.2f ms; %d chunks; frame adds %d draw calls, %d primitives, %d objects" % [
				_wires.call(&"span_count"), _phase_frames - SETTLE,
				float(_wires.get(&"slowest_build_usec")) / 1000.0, float(_wires.get(&"slowest_apply_usec")) / 1000.0,
				float(_wires.get(&"slowest_frame_usec")) / 1000.0, (_wires.call(&"chunk_nodes") as Array).size(),
				int(after["draws"]) - int(_before["draws"]), int(after["primitives"]) - int(_before["primitives"]),
				int(after["objects"]) - int(_before["objects"])])
			_wires.set(&"slowest_frame_usec", 0)
			_phase = "one"
			_phase_frames = 0
			_idle_ticks = 0
			_wires.call(&"set_spans", "line0", _sets["line0"])
		elif _phase == "one":
			print("wires: threaded, one owner's %d spans again: built over %d frames; most wire time in a frame %.2f ms" % [
				_sets["line0"].size(), _phase_frames - SETTLE, float(_wires.get(&"slowest_frame_usec")) / 1000.0])
			_phase = ""


## Everything built at once on this thread, in a module of its own that is then dropped.
func _at_once() -> void:
	var wires: Node = (load(WIRES) as GDScript).new()
	add_child(wires)
	var spans := 0
	var started := Time.get_ticks_usec()
	for owner: String in _sets:
		wires.call(&"set_spans", owner, _sets[owner])
		spans += _sets[owner].size()
	var taken := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	wires.call(&"flush")
	var built := Time.get_ticks_usec() - started
	print("wires: at once, %d spans: taken in %.1f ms, built in %.1f ms (%.1f us a span); slowest unit %.2f ms (arrays) + %.2f ms (mesh and node)" % [
		spans, float(taken) / 1000.0, float(built) / 1000.0, float(taken + built) / float(spans),
		float(wires.get(&"slowest_build_usec")) / 1000.0, float(wires.get(&"slowest_apply_usec")) / 1000.0])
	remove_child(wires)
	wires.free()


func _make_sets() -> void:
	for line in LINES:
		var group := []
		for i in POLES - 1:
			for h: float in [7.6, 7.2, 6.8]:
				group.append(_span(Vector3(-200.0 + float(i) * 40.0, h, -20.0 - float(line) * 20.0), Vector3(40, 0, 0), &"low_voltage"))
		_sets["line%d" % line] = group
	for fence in FENCES:
		var group := []
		for i in PANELS:
			for h: float in [0.45, 0.85, 1.25]:
				group.append(_span(Vector3(-30.0 + float(i) * 3.0, h, -10.0 - float(fence) * 40.0), Vector3(3, 0, 0), &"barbed"))
		_sets["fence%d" % fence] = group


## A span from `start` (x, height above ground, z) along `step`, both ends on the ground.
func _span(start: Vector3, step: Vector3, kind: StringName) -> Dictionary:
	var a := VoxelWorld.spawn_of(_world, start)
	var b := VoxelWorld.spawn_of(_world, start + step)
	return {"from": a, "to": b, "kind": kind}


func _frame_info() -> Dictionary:
	return {
		"draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
	}

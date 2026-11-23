extends Node
## Power lines on the map (#494): the substation yard with a terminal gantry for each
## high-voltage line, a lattice pylon at every other point of a high-voltage line and a wooden
## pole at every point of a pole line, from the map's lines (VoxelWorld.map_power_lines,
## map_power_substation) laid out by PowerLayout, with the wires hung between neighbours
## through the wires module. Every machine builds them from the map on `world.ready`, so
## nothing is sent. A server puts the pieces up at once (collision only); a client a few a
## frame, nearest first, pieces alike sharing their meshes (built off the main thread). They
## start standing and are not saved.

var config: Dictionary = {}
var towers: Array[VoxPiece] = []
## True puts every tower up as soon as the world is ready (a server, which draws nothing).
var all_at_once := DisplayServer.get_name() == "headless"
## The layout this map got: {towers, wires} (see PowerLayout.plan).
var layout: Dictionary = {}

var _queue: Array[Dictionary] = []
var _near := Vector3.ZERO
var _planned := false


func _ready() -> void:
	var data: Variant = Data.load_json(PowerLayout.CONFIG)
	if not (data is Dictionary and Data.require(PowerLayout.CONFIG, data, PowerLayout.REQUIRED)):
		return
	var problems := PowerLayout.check(data)
	for problem in problems:
		Log.error(&"power", "%s: %s" % [PowerLayout.CONFIG, problem])
	if not problems.is_empty():
		return
	config = data
	EventBus.subscribe(&"world.ready", _on_world_ready)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
	# The shared meshes are this world's towers'; the next world may have others.
	VoxPiece.clear_shared()


func _on_world_ready(p: Dictionary) -> void:
	if _planned or config.is_empty():
		return
	# The flat test world has no power lines.
	var ground := get_tree().get_first_node_in_group(&"ground")
	if ground == null or not ground.has_method(&"map_power_lines"):
		return
	_planned = true
	_near = p.get("spawn", Vector3.ZERO)
	var t := Prof.start()
	var station: Dictionary = ground.call(&"map_power_substation") if ground.has_method(&"map_power_substation") else {}
	layout = PowerLayout.plan(ground.call(&"map_power_lines"), station, config, Callable(ground, &"ground_height"))
	_queue.assign(layout["towers"])
	for wire_set: Dictionary in layout["wires"]:
		EventBus.publish(&"wires.set", wire_set)
	Prof.stop(&"power/plan", t)
	if all_at_once:
		build_all()


func pending() -> int:
	return _queue.size()


func build_all() -> void:
	var t := Prof.start()
	while not _queue.is_empty():
		_put_up(_queue.pop_front())
	Prof.stop(&"power/build", t)


func _process(_delta: float) -> void:
	if _queue.is_empty():
		return
	var t := Prof.start()
	var camera := get_viewport().get_camera_3d()
	var near := camera.global_position if camera != null else _near
	for i in maxi(int(config["builds_per_frame"]), 1):
		if _queue.is_empty():
			break
		_put_up(_queue.pop_at(_nearest(near)))
	Prof.stop(&"power/build", t)


func _nearest(to: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in _queue.size():
		var d := to.distance_squared_to((_queue[i]["transform"] as Transform3D).origin)
		if d < best_d:
			best_d = d
			best = i
	return best


func _put_up(p: Dictionary) -> void:
	var piece := VoxPiece.new()
	piece.name = "%s%d" % [str(p["generator"]).trim_prefix("Vox"), towers.size()]
	piece.generator = p["generator"]
	piece.params = p["params"]
	piece.shared = true
	piece.lods = p["lods"]
	piece.lod_fade = p["fade"]
	piece.transform = p["transform"]
	piece.set_meta(&"power_line", p["line"])
	add_child(piece)
	towers.append(piece)

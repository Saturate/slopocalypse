extends Node3D
## Capture setup (#391): the camera drives from the city out across the map at `--speed=`
## metres a second (30 by default) with scenery streaming as in play, and every frame's time
## spent building scenery is logged. At the end it prints the worst frames, what each kind of
## build step cost, and how many frames the ground under the camera was missing its chunk,
## grass or road (what the player would see popping in).

const WORLD := "res://modules/world/scenes/world.tscn"
const CITY := "res://modules/city/city_module.gd"
const ZONE := "world/scenery_build"
const HEIGHT := 2.0
## Metres driven before the summary.
const DRIVE := 1500.0
## Zones read from Prof each frame: more than run in one.
const ZONES_READ := 200

var _camera := Camera3D.new()
var _scatter: SceneryScatter
var _map: GroundShape
var _from := Vector3.ZERO
var _heading := Vector3.RIGHT
var _speed := 30.0
var _travelled := 0.0
var _frames: Array[float] = []
## Metres driven at each frame the camera's chunk was missing or unfinished.
var _missing: Array[float] = []
var _unfinished: Array[float] = []
var _done := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--speed=") and arg.trim_prefix("--speed=").is_valid_float():
			_speed = float(arg.trim_prefix("--speed="))
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_scatter = world.get_node("Scenery")
	_map = WorldMaps.shape_or_default()
	var city: Node = (load(CITY) as GDScript).new()
	add_child(city)
	city.call(&"_on_world_ready", {})
	var site: Node3D = city.get(&"site")
	_from = site.global_position if site != null else _scatter.home
	# Toward the middle of the map, so the drive stays on it.
	var middle := _map.extent().get_center()
	_heading = Vector3(middle.x - _from.x, 0.0, middle.y - _from.z).normalized()
	if _heading.is_zero_approx():
		_heading = Vector3.RIGHT
	_camera.far = 900.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child((world.get_node("Terrain") as VoxelWorld).make_viewer())
	_place()
	Prof.take()
	Prof.take_frame(ZONES_READ)


func _process(delta: float) -> void:
	if _scatter == null or _done:
		return
	var frame := Prof.take_frame(ZONES_READ)
	var spent := 0.0
	for zone: String in frame:
		# Only the outer zones: the sub-zones nest inside the steps.
		if zone == ZONE or zone.begins_with(ZONE + "/"):
			spent += float(frame[zone])
	_frames.append(spent)
	var here := _scatter.chunk_at(_camera.global_position.x, _camera.global_position.z)
	if here >= 0 and _scatter.chunk_node(here) == null:
		_missing.append(snappedf(_travelled, 0.1))
	elif (_scatter.get(&"_building") as Dictionary).has(here):
		_unfinished.append(snappedf(_travelled, 0.1))
	_travelled += _speed * delta
	_place()
	if _travelled > DRIVE:
		_done = true
		_summary()


func _place() -> void:
	var at := _from + _heading * _travelled
	at.y = _map.height_at(at.x, at.z) + HEIGHT
	_camera.global_position = at
	_camera.look_at(at + _heading * 10.0 + Vector3.DOWN)


func _summary() -> void:
	var sorted := _frames.duplicate()
	sorted.sort()
	var budget := float((_scatter.get(&"_cfg") as Dictionary)["build_budget_ms"])
	var over := 0
	for f: float in _frames:
		if f > budget:
			over += 1
	print("scenery build per frame over %d frames: median %.2f, p99 %.2f, max %.2f ms; frames over the %.1f ms budget: %d" % [sorted.size(), sorted[sorted.size() / 2], sorted[int(sorted.size() * 0.99)], sorted[-1], budget, over])
	var stats := Prof.take()
	var zones := stats.keys()
	zones.sort()
	for zone: String in zones:
		if zone.begins_with(ZONE):
			var z: Dictionary = stats[zone]
			print("  %-34s calls %5d  mean %6.2f  max %6.2f ms" % [zone, int(z["calls"]), float(z["ms"]) / maxf(float(z["calls"]), 1.0), float(z["max_ms"])])
	print("camera's chunk missing at metres %s; still putting in grass or road at %s" % [_missing, _unfinished])

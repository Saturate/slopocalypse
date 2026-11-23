extends Node3D
## Capture setup: six stops on a generated map (#472): the camp looking down the highway,
## the highway further on, the city from its edge, a farm, a hilltop antenna and a lone
## cabin, each from a little above the ground. Recipe and seed from `--map=` / `--seed=`
## (the world.json defaults otherwise).

const WORLD := "res://modules/world/scenes/world.tscn"
const CONFIG := "res://modules/world/data/world.json"
const FRAMES_PER_STOP := 300

var _camera := Camera3D.new()
var _map: MapShape
var _scatter: SceneryScatter
var _voxels: VoxelWorld
var _stops: Array[Array] = []
var _ticks := 0
## `--stop=N`: only that stop, held (to look at one place closely).
var _only := -1


func _ready() -> void:
	var cfg: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(CONFIG)) as Dictionary)["map"]
	var recipe := str(cfg["recipe"])
	var seed_value := int(cfg["seed"])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			recipe = arg.trim_prefix("--map=")
		elif arg.begins_with("--seed=") and arg.trim_prefix("--seed=").is_valid_int():
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--stop=") and arg.trim_prefix("--stop=").is_valid_int():
			_only = int(arg.trim_prefix("--stop="))
	WorldMaps.select(recipe, seed_value)
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_voxels = world.get_node("Terrain")
	_scatter = world.get_node("Scenery")
	_map = WorldMaps.shape()
	_camera.fov = 70.0
	_camera.far = 1500.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(_voxels.make_viewer())
	var camp := _map.camp()
	var forward := _map.forward()
	_stops.append([camp + Vector3.UP * 3.0 - forward * 6.0, camp + forward * 60.0])
	# Above the road itself: beside it the camera can sit inside a cut's bank.
	_stops.append([_map.road_point(380.0) + Vector3.UP * 6.0, _map.road_point(470.0)])
	var places: Settlements = _map.map["places"]
	var city: Rect2 = places.city()["footprint"]
	var edge := Vector3(city.position.x - 40.0, 0.0, city.get_center().y)
	edge.y = _map.height_at(edge.x, edge.z) + 12.0
	_stops.append([edge, Vector3(city.get_center().x, _map.height_at(city.get_center().x, city.get_center().y), city.get_center().y)])
	for kind in ["farm", "antenna", "cabin"]:
		for site: Dictionary in (_map.map["sites"] as MapSites).sites():
			if site["kind"] == kind:
				var c: Vector2 = site["centre"]
				var at := Vector3(c.x + 30.0, 0.0, c.y + 30.0)
				at.y = _map.height_at(at.x, at.z) + 8.0
				_stops.append([at, Vector3(c.x, float(site["level"]), c.y)])
				break
	_go(maxi(_only, 0))


func _process(_delta: float) -> void:
	if _map == null:
		return
	_ticks += 1
	# The contact sheet takes its first frame after FRAMES_PER_STOP ticks: each stop is
	# moved to halfway between frames, so stop N is loaded when frame N+1 is taken.
	if _only < 0 and _ticks > FRAMES_PER_STOP and _ticks % FRAMES_PER_STOP == FRAMES_PER_STOP / 2:
		_go(_ticks / FRAMES_PER_STOP)


func _go(stop: int) -> void:
	if stop >= _stops.size():
		return
	var at: Vector3 = _stops[stop][0]
	_camera.global_position = at
	_camera.look_at(_stops[stop][1])
	_scatter.update_around([at], INF)
	_voxels.update_around([at], INF)

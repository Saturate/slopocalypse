extends Node3D
## Capture setup (#472): the city on a generated map, one view a sheet frame: down the
## highway toward the city, from above its road side, along the ring street to where the road comes in, and from
## the far side. Recipe and seed from `--map=` / `--seed=` (world.json defaults otherwise).

const WORLD := "res://modules/world/scenes/world.tscn"
const CITY := "res://modules/city/city_module.gd"
const CONFIG := "res://modules/world/data/world.json"
const SHOT := 240

var _camera := Camera3D.new()
var _ticks := 0
var _site: CitySite
var _map: MapShape
var _voxels: VoxelWorld
var _scatter: SceneryScatter


func _ready() -> void:
	var cfg: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(CONFIG)) as Dictionary)["map"]
	var recipe := str(cfg["recipe"])
	var seed_value := int(cfg["seed"])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			recipe = arg.trim_prefix("--map=")
		elif arg.begins_with("--seed=") and arg.trim_prefix("--seed=").is_valid_int():
			seed_value = int(arg.trim_prefix("--seed="))
	WorldMaps.select(recipe, seed_value)
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_voxels = world.get_node("Terrain")
	_scatter = world.get_node("Scenery")
	_map = WorldMaps.shape()
	var city: Node = (load(CITY) as GDScript).new()
	add_child(city)
	city.call(&"_on_world_ready", {})
	_site = city.get(&"site")
	_camera.fov = 70.0
	_camera.far = 1200.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(_voxels.make_viewer())
	_shot(0)


func _process(_delta: float) -> void:
	if _site == null:
		return
	_ticks += 1
	# The sheet's first frame is taken after SHOT ticks: move on halfway between frames.
	if _ticks > SHOT and _ticks % SHOT == SHOT / 2:
		_shot(_ticks / SHOT)


func _shot(n: int) -> void:
	var where := _site.global_transform
	var half := float(_site.config["size"]) / 2.0
	var shots := [
		[where * Vector3(0.0, 8.0, -half - 90.0), where * Vector3(0.0, 4.0, 0.0)],
		[where * Vector3(-half * 0.6, 40.0, -half - 50.0), where * Vector3(0.0, 0.0, -half * 0.3)],
		# On the ring street along the road side, looking along it to where the road comes in.
		[where * Vector3(-half * 0.6, 1.7, -half + 4.0), where * Vector3(0.0, 1.7, -half - 10.0)],
		[where * Vector3(half * 0.3, 60.0, half + 80.0), where * Vector3(0.0, 0.0, 0.0)],
	]
	if n >= shots.size():
		return
	var at: Vector3 = shots[n][0]
	_camera.global_position = at
	_camera.look_at(shots[n][1])
	_scatter.update_around([at, where.origin], INF)
	_voxels.update_around([at, where.origin], INF)

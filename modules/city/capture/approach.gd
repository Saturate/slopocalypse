extends Node3D
## Capture setup, one shot a sheet frame: the street in from the road (#403) from the road at
## eye height, the junction from above, the ramp from the side, and a player standing on a
## city street seen at ankle height.

const WORLD := "res://modules/world/scenes/world.tscn"
const CITY := "res://modules/city/city_module.gd"
const PLAYER := "res://modules/player/scenes/player.tscn"
const SHOT := 60
const SETTLE := 10

var _camera := Camera3D.new()
var _ticks := 0
var _city: Node
var _site: CitySite
var _lead: Dictionary


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var terrain := world.get_node("Terrain") as VoxelWorld
	_city = (load(CITY) as GDScript).new()
	add_child(_city)
	_city.call(&"_on_world_ready", {})
	_site = _city.get(&"site")
	_lead = _site.approach
	_camera.fov = 70.0
	_camera.far = 800.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(terrain.make_viewer())
	var player: PlayerController = (load(PLAYER) as PackedScene).instantiate()
	add_child(player)
	player.global_position = _site.global_transform * Vector3(float(_lead["x"]), 0.5, -float(_site.config["size"]) / 2.0 + 4.0)
	_shot(0)
	(world.get_node("Scenery") as SceneryScatter).update_around([_site.global_position], INF)
	terrain.update_around([_site.global_position, _site.global_transform * Vector3(float(_lead["x"]), 0.0, float(_lead["from"]))], INF)


func _process(_delta: float) -> void:
	if _site == null:
		return
	_ticks += 1
	if _ticks % SHOT == SETTLE:
		_shot(_ticks / SHOT)


func _look(from: Vector3, to: Vector3) -> void:
	_camera.global_position = _site.global_transform * from
	_camera.look_at(_site.global_transform * to)


func _shot(i: int) -> void:
	var x := float(_lead["x"])
	var from := float(_lead["from"])
	var to := float(_lead["to"])
	var drop := float(_lead["drop"])
	match i:
		0:
			_look(Vector3(x - 3.0, drop + 1.7, float(_lead["road"]) - 6.0), Vector3(x, 1.0, to + 10.0))
		1:
			_look(Vector3(x + 30.0, 45.0, from - 25.0), Vector3(x, 0.0, (from + to) / 2.0))
		2:
			_look(Vector3(x + 40.0, drop / 2.0 + 12.0, (from + to) / 2.0), Vector3(x, drop / 2.0, (from + to) / 2.0))
		3:
			_look(Vector3(x + 3.0, 0.15, to + 4.0), Vector3(x, 0.2, to + 4.0))

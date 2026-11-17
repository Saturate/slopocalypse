extends Node3D
## Capture setup: the city from a street at eye height, then from above over its blocks and
## square, then from a passage looking into a courtyard.

const WORLD := "res://modules/world/scenes/world.tscn"
const CITY := "res://modules/city/city_module.gd"

var _camera := Camera3D.new()
var _ticks := 0
var _city: Node
var _site: CitySite


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var terrain := world.get_node("Terrain") as VoxelWorld
	_city = (load(CITY) as GDScript).new()
	add_child(_city)
	_city.call(&"_on_world_ready", {})
	_site = _city.get(&"site")
	_camera.fov = 75.0
	_camera.far = 800.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(terrain.make_viewer())
	_shot_street()
	(world.get_node("Scenery") as SceneryScatter).update_around([_site.global_position], INF)
	terrain.update_around([_site.global_position], INF)


## Down the second street across the city, from its near end, at eye height.
func _shot_street() -> void:
	var street: Rect2 = (_site.plan["streets"] as Array)[2]
	var near := Vector3(street.get_center().x, 1.7, street.position.y + 4.0)
	var far := Vector3(street.get_center().x, 4.0, street.end.y)
	_camera.global_position = _site.global_transform * near
	_camera.look_at(_site.global_transform * far)


func _process(_delta: float) -> void:
	if _site == null:
		return
	_ticks += 1
	if _ticks == 120:
		var size := float(_site.config["size"])
		# High and steep, from the side away from the afternoon sun, so courtyards and the
		# square show.
		_camera.global_position = _site.global_transform * Vector3(size * 0.25, 95.0, size * 0.55)
		_camera.look_at(_site.global_transform * Vector3(0.0, 0.0, -size * 0.05))
	if _ticks == 240:
		var passage: Rect2 = (_site.plan["passages"] as Array)[0]
		# From across the street, looking through the passage into the courtyard.
		var from := Vector3(passage.get_center().x + 1.0, 1.7, passage.position.y - 12.0)
		var to := Vector3(passage.get_center().x, 1.8, passage.get_center().y + 4.0)
		_camera.global_position = _site.global_transform * from
		_camera.look_at(_site.global_transform * to)

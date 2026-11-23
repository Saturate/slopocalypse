extends Node3D
## Capture setup, one shot a sheet frame: down an avenue at eye height, across a zebra
## crossing at a junction, the city from high above, along the rooftops of a street front,
## in front of a gateway looking through it, and from the courtyard back out through it.
## The lights module is added when it is there, so the city's lamps stand.

const WORLD := "res://modules/world/scenes/world.tscn"
const CITY := "res://modules/city/city_module.gd"
const LIGHTS := "res://modules/lights/lights_module.gd"
## Frames per shot (the capture grabs one every 60 at --frames 360 --sheet 6). Ticks here
## start once the world has loaded, some frames after the capture's own count, so each shot
## is set up this many ticks into its stretch.
const SHOT := 60
const SETTLE := 10

var _camera := Camera3D.new()
var _ticks := 0
var _city: Node
var _site: CitySite


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var terrain := world.get_node("Terrain") as VoxelWorld
	if ResourceLoader.exists(LIGHTS):
		add_child((load(LIGHTS) as GDScript).new())
	_city = (load(CITY) as GDScript).new()
	add_child(_city)
	_city.call(&"_on_world_ready", {})
	_site = _city.get(&"site")
	_camera.fov = 75.0
	_camera.far = 800.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(terrain.make_viewer())
	_shot(0)
	(world.get_node("Scenery") as SceneryScatter).update_around([_site.global_position], INF)
	terrain.update_around([_site.global_position], INF)


func _process(_delta: float) -> void:
	if _site == null:
		return
	_ticks += 1
	if _ticks % SHOT == SETTLE:
		_shot(_ticks / SHOT)


func _look(from: Vector3, to: Vector3) -> void:
	_camera.global_position = _site.global_transform * from
	_camera.look_at(_site.global_transform * to)


## A gateway in a front facing -z, so its courtyard lies toward +z.
func _gateway() -> Rect2:
	for b: Dictionary in _site.plan["buildings"]:
		if b.has("gateway") and b["facing"] == Vector2(0, -1):
			return b["gateway"]
	return (_site.plan["passages"] as Array)[0]


func _shot(i: int) -> void:
	var plan := _site.plan
	var size := float(_site.config["size"])
	match i:
		0:
			# Down the first avenue (x-line 1) from its near end, on the pavement edge.
			var street: Rect2 = (plan["streets"] as Array)[2]
			_look(Vector3(street.position.x + 2.0, 1.7, street.position.y + 10.0), Vector3(street.get_center().x, 3.0, street.end.y - 20.0))
		1:
			# A junction of two avenues, from a pavement corner across its zebra crossings.
			var crossing: Rect2 = (plan["crossings"] as Array)[2]
			_look(Vector3(crossing.position.x - 3.0, 1.7, crossing.end.y + 5.0), Vector3(crossing.end.x + 6.0, 0.5, crossing.position.y - 8.0))
		2:
			# High and steep, from the side away from the afternoon sun, so courtyards and the
			# square show.
			_look(Vector3(size * 0.25, 95.0, size * 0.55), Vector3(0.0, 0.0, -size * 0.05))
		3:
			# Low over the rooftops, along the street fronts on the near ring.
			_look(Vector3(-size * 0.55, 28.0, -size * 0.62), Vector3(size * 0.1, 8.0, -size * 0.35))
		4:
			var gate := _gateway()
			_look(Vector3(gate.get_center().x + 1.0, 1.7, gate.position.y - 9.0), Vector3(gate.get_center().x, 1.9, gate.end.y + 4.0))
		5:
			var gate := _gateway()
			_look(Vector3(gate.get_center().x - 2.0, 1.7, gate.end.y + 9.0), Vector3(gate.get_center().x, 2.2, gate.position.y))

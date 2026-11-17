extends Node3D
## Capture setup: the city's guards on their spots, with player bodies standing in for
## soldiers: from a street (window and corner guards), then from above (roofs, patrols).

const WORLD := "res://modules/world/scenes/world.tscn"
const CITY := "res://modules/city/city_module.gd"
const BODY := "res://modules/player/scenes/player.tscn"


class Stand extends Node:
	var bodies: Array[Node3D] = []

	func _ready() -> void:
		add_to_group(&"enemies_api")

	func server_spawn_guard(at: Vector3, yaw: float, route: Array = []) -> Node:
		var body: PlayerController = (load(BODY) as PackedScene).instantiate()
		body.set_physics_process(false)
		add_child(body)
		body.global_position = at
		body.rotation.y = yaw
		bodies.append(body)
		return body


var _camera := Camera3D.new()
var _ticks := 0
var _city: Node
var _stand := Stand.new()


func _ready() -> void:
	add_child(_stand)
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var terrain := world.get_node("Terrain") as VoxelWorld
	_city = (load(CITY) as GDScript).new()
	add_child(_city)
	_city.call(&"_on_world_ready", {})
	_camera.fov = 70.0
	_camera.far = 800.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(terrain.make_viewer())
	var site: CitySite = _city.get(&"site")
	(world.get_node("Scenery") as SceneryScatter).update_around([site.global_position], INF)
	terrain.update_around([site.global_position], INF)


func _process(_delta: float) -> void:
	_ticks += 1
	if _stand.bodies.is_empty():
		return
	var ground := (_city.get(&"site") as CitySite).global_position.y
	if _ticks == 60:
		# A window guard, from the street, level with its floor, 8 m out.
		var g := _stand.bodies[0]
		var out := -g.global_basis.z
		_camera.global_position = g.global_position + out * 8.0 + Vector3.UP * 1.5
		_camera.look_at(g.global_position + Vector3.UP * 1.2)
	elif _ticks == 180:
		# A guard on the pavement (a corner post), from across the junction.
		for g in _stand.bodies:
			if absf(g.global_position.y - ground) < 0.5:
				var out := -g.global_basis.z
				_camera.global_position = g.global_position + out * 10.0 + Vector3.UP * 1.7
				_camera.look_at(g.global_position + Vector3.UP * 1.0)
				break

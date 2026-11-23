extends Node3D
## Capture base: the players' camp on the default map with what stands in it (the fence and
## hut, the mission board, the transport, the trader's stall and the players' car), the camera moving between
## two camp-local spots ([x, height, z] metres: x to the right as you face the gate, z toward
## the gate, height over the pad) and looking at a third, with the sun behind the camera.

const WORLD := "res://modules/world/scenes/world.tscn"
const MODULES: Array[String] = ["res://modules/camp/camp_module.gd", "res://modules/missions/missions_module.gd", "res://modules/trader/trader_module.gd", "res://modules/car/car_module.gd"]
## The sun comes from behind the camera, this far round to one side (radians) and this high
## (radians over the horizon), so the side facing the camera is lit.
const SUN_SIDE := 0.5
const SUN_HIGH := 0.8
## Seconds the camera takes from `from` to `to`.
const MOVE_SECONDS := 3.0

var from := Vector3(0.0, 1.8, 60.0)
var to := Vector3(0.0, 1.8, 35.0)
var look := Vector3(0.0, 1.5, 0.0)
var fov := 70.0

var _camera := Camera3D.new()
var _camp: CampLayout
var _t := 0.0


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var terrain: VoxelWorld = world.get_node("Terrain")
	for path in MODULES:
		add_child((load(path) as GDScript).new())
	_camp = world.get("camp")
	var car := world.get_node("CarSpawn") as Node3D
	EventBus.publish(&"world.ready", {"spawn": VoxelWorld.spawn_of(world, Vector3.UP), "camp": _camp, "car": car.global_transform})
	_camera.fov = fov
	_camera.far = 900.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(terrain.make_viewer())
	_place(0.0)
	var sun := world.get_node("Sun") as DirectionalLight3D
	var ahead := _point(look) - _camera.global_position
	ahead.y = 0.0
	var flat := ahead.normalized().rotated(Vector3.UP, SUN_SIDE)
	sun.global_basis = Basis.looking_at((flat * cos(SUN_HIGH) + Vector3.DOWN * sin(SUN_HIGH)).normalized(), Vector3.UP)
	terrain.update_around([_camp.centre, _camera.global_position], INF)
	(world.get_node("Scenery") as SceneryScatter).update_around([_camp.centre, _camera.global_position], INF)


func _process(delta: float) -> void:
	if _camp == null:
		return
	_t += delta
	_place(clampf(_t / MOVE_SECONDS, 0.0, 1.0))


func _point(local: Vector3) -> Vector3:
	return _camp.point(Vector2(local.x, local.z)) + Vector3.UP * local.y


func _place(share: float) -> void:
	_camera.global_position = _point(from.lerp(to, share))
	_camera.look_at(_point(look))

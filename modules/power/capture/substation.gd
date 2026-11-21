extends Node3D
## Capture setup: the default map's substation yard from 35 m off and 14 m up, looking down
## into it across the fence, so the transformers, the hut, the fence and the terminal gantries
## with their lines leaving all show; the camera swings a little round the yard over the
## frames. Lit from behind the camera and to one side.

const WORLD := "res://modules/world/scenes/world.tscn"
const POWER := "res://modules/power/power_module.gd"
const WIRES := "res://modules/wires/wires_module.gd"
const OFF := 35.0
const UP := 14.0
## How far round the yard the camera starts from the side the first line leaves by, and how
## far it swings over the frames (radians).
const START := 2.4
const SWING := 0.35
const SUN_SIDE := 0.7
const SUN_HIGH := 0.6

var _camera := Camera3D.new()
var _terrain: VoxelWorld
var _centre := Vector3.ZERO
var _out := Vector3.FORWARD
var _t := 0.0


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_terrain = world.get_node("Terrain")
	var wires: Node = (load(WIRES) as GDScript).new()
	add_child(wires)
	var power: Node = (load(POWER) as GDScript).new()
	add_child(power)
	EventBus.publish(&"world.ready", {"spawn": VoxelWorld.spawn_of(world)})
	power.call(&"build_all")
	wires.call(&"flush")
	var station := _terrain.map_power_substation()
	if station.is_empty():
		push_error("no substation on this map")
		return
	_centre = station["centre"]
	for line: Dictionary in _terrain.map_power_lines():
		if line["from"] == "substation":
			var first: Vector3 = (line["points"] as Array)[0]
			_out = Vector3(first.x - _centre.x, 0.0, first.z - _centre.z).normalized()
			break
	_camera.fov = 70.0
	_camera.far = 2500.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(_terrain.make_viewer())
	_place(0.0)
	var sun := world.get_node("Sun") as DirectionalLight3D
	var ahead := -_camera.global_basis.z
	ahead.y = 0.0
	var flat := ahead.normalized().rotated(Vector3.UP, SUN_SIDE)
	sun.global_basis = Basis.looking_at((flat * cos(SUN_HIGH) + Vector3.DOWN * sin(SUN_HIGH)).normalized(), Vector3.UP)
	var focus: Array[Vector3] = [_centre, _camera.global_position]
	_terrain.update_around(focus, INF)
	var scenery := world.get_node("Scenery") as SceneryScatter
	# Nothing between the camera and the yard: the shot is of the yard, not a tree by it.
	var between := _centre + _out.rotated(Vector3.UP, START + SWING / 2.0) * OFF * 0.6
	scenery.set_clearings_for(&"capture", [{"at": between, "radius": OFF * 0.6}])
	scenery.update_around(focus, INF)


func _process(delta: float) -> void:
	if _centre == Vector3.ZERO:
		return
	_t += delta
	_place(clampf(_t / 3.0, 0.0, 1.0))


func _place(share: float) -> void:
	var dir := _out.rotated(Vector3.UP, START + SWING * share)
	var at := _centre + dir * OFF
	at.y = _terrain.surface_height(at.x, at.z) + UP
	_camera.global_position = at
	_camera.look_at(_centre + Vector3.UP * 2.0)

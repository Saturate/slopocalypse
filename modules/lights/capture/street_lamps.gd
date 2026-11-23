extends Node3D
## Capture setup: standing on the road at night, looking along a row of street lamps. At
## `BREAK_AT` the nearest bulb is shot out (their light goes, glass falls).

const WORLD := "res://modules/world/scenes/world.tscn"
const LIGHTS := "res://modules/lights/lights_module.gd"
const BREAK_AT := 150

var _camera := Camera3D.new()
var _ticks := 0
var _lights: Node
var _ready_done := false


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var terrain := world.get_node("Terrain") as VoxelWorld
	var clock := DayClock.from_data()
	var lighting := DayLighting.new()
	add_child(lighting)
	lighting.attach(world.get_node("Sun") as DirectionalLight3D, (world.get_node("Environment") as WorldEnvironment).environment)
	clock.set_hour(22.5)
	lighting.apply(clock)
	_lights = (load(LIGHTS) as GDScript).new()
	add_child(_lights)
	var road: Dictionary = (_lights.get(&"config") as Dictionary)["road"]
	var spots: Array[Transform3D] = (load(LIGHTS) as GDScript).call(&"road_spots",
		func(m: float) -> Vector3: return terrain.road_point(m),
		func(x: float, z: float) -> float: return terrain.heights.height_at(x, z),
		road)
	_lights.call(&"place", spots)
	var from := terrain.road_point(0.0) + Vector3(-2.0, 4.0, 0.0)
	var aim := terrain.road_point(38.0) + Vector3.UP * 0.5
	_camera.fov = 75.0
	_camera.far = 600.0
	add_child(_camera)
	_camera.current = true
	_camera.global_position = from
	_camera.look_at(aim)
	_camera.add_child(terrain.make_viewer())
	(world.get_node("Scenery") as SceneryScatter).update_around([from], INF)
	terrain.update_around([from], INF)
	_ready_done = true


func _process(_delta: float) -> void:
	if not _ready_done:
		return
	_ticks += 1
	if _ticks == BREAK_AT:
		Net.server_broadcast(&"lights.lamp_broken", {"id": 0})

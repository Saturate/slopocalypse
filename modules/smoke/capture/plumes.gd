extends Node3D
## Capture setup: from beside the road, a blast 16 m off (a fog plume), a drone crash 30 m
## off (a dithered particle plume) and a blast 150 m off (past the fog's reach, so particles)
## at midday; then the same again at dusk.

const WORLD := "res://modules/world/scenes/world.tscn"
const SMOKE := "res://modules/smoke/smoke_module.gd"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const DUSK_AT := 200
## Frame -> [metres ahead, metres across, kind]
const BLASTS := {
	8: [16.0, -2.0, "blast"], 14: [30.0, -7.0, "drone"], 20: [150.0, 0.0, "blast"],
	DUSK_AT + 8: [16.0, -2.0, "blast"], DUSK_AT + 14: [30.0, -7.0, "drone"], DUSK_AT + 20: [150.0, 0.0, "blast"],
}

var _camera := Camera3D.new()
var _ticks := 0
var _clock: DayClock
var _lighting := DayLighting.new()
var _terrain: VoxelWorld
var _forward := Vector3.FORWARD
var _right := Vector3.RIGHT
var _from := Vector3.ZERO


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	add_child((load(WEAPONS) as GDScript).new())
	add_child((load(SMOKE) as GDScript).new())
	var terrain := world.get_node("Terrain") as VoxelWorld
	_terrain = terrain
	_clock = DayClock.from_data()
	add_child(_lighting)
	_lighting.attach(world.get_node("Sun") as DirectionalLight3D, (world.get_node("Environment") as WorldEnvironment).environment)
	_clock.set_hour(13.0)
	_lighting.apply(_clock)
	_from = terrain.road_point(14.0) + Vector3.UP * 3.0
	_camera.fov = 70.0
	_camera.far = 900.0
	add_child(_camera)
	_camera.current = true
	_camera.global_position = _from
	_camera.look_at(terrain.road_point(44.0) + Vector3.UP * 3.0)
	_forward = -_camera.global_basis.z
	_forward.y = 0.0
	_forward = _forward.normalized()
	_right = _forward.cross(Vector3.UP)
	_camera.add_child(terrain.make_viewer())
	(world.get_node("Scenery") as SceneryScatter).update_around([_from], INF)
	terrain.update_around([_from], INF)


func _process(_delta: float) -> void:
	if _clock == null:
		return
	_ticks += 1
	if _ticks == DUSK_AT:
		_clock.set_hour(19.1)
		_lighting.apply(_clock)
	if BLASTS.has(_ticks):
		var b: Array = BLASTS[_ticks]
		# Along the road, so the trees either side don't hide them.
		var at := _terrain.road_point(14.0 + float(b[0])) + _right * float(b[1])
		at.y = _terrain.ground_height(at.x, at.z) + 0.5
		Net.server_broadcast(&"explosion", {"position": at, "radius": 3.0, "source": null, "kind": b[2]})

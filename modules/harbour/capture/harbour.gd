extends Node3D
## Capture setup: the harbour by the camp (#454) on the default map, one shot every
## SHOT_FRAMES frames: the jetty from the shore at eye height, from beside it on the beach,
## along its deck from the shore end, back at the shore from its sea end, from a swimmer by
## its ladder, and the harbour and the camp from above. `--frames 360 --sheet 6`.

const WORLD := "res://modules/world/scenes/world.tscn"
const MODULE := "res://modules/harbour/harbour_module.gd"
const SHOT_FRAMES := 60
const EYE := 1.7

var _camera := Camera3D.new()
var _ticks := 0
var _terrain: VoxelWorld
var _scenery: SceneryScatter
## Each [camera, target], in world space.
var _shots: Array[Array] = []


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_terrain = world.get_node("Terrain") as VoxelWorld
	_scenery = world.get_node("Scenery") as SceneryScatter
	var map := _terrain.heights as MapShape
	if map == null or map.harbour().is_empty():
		Log.info(&"capture", "%s: this map has no harbour to film" % get_script().resource_path)
		get_tree().quit(0)
		return
	var module: Node = (load(MODULE) as GDScript).new()
	add_child(module)
	EventBus.publish(&"world.ready", {"harbour": map.harbour()})
	var line := HarbourPlan.jetty_line(map.harbour(), _terrain.ground_height, module.get(&"config"))
	var start: Vector3 = line["start"]
	var facing: Vector3 = line["facing"]
	var end := start + facing * float(line["length"])
	var deck := float(line["deck"])
	var right := facing.cross(Vector3.UP)
	var middle := start.lerp(end, 0.5)
	_shots.append([_on_ground(start - facing * 14.0 + right * 3.0, EYE), end + Vector3.UP * 1.0])
	_shots.append([_on_ground(start - facing * 2.0 - right * 16.0, EYE), middle - right * 2.0])
	_shots.append([start + Vector3.UP * EYE - facing * 0.5, end + facing * 20.0 + Vector3.UP * EYE])
	_shots.append([end + Vector3.UP * EYE - facing * 0.5, start - facing * 25.0 + Vector3.UP * 2.0])
	_shots.append([Vector3(end.x, deck - 0.6, end.z) + facing * 4.0 + right * 2.5, Vector3(end.x, deck + 0.5, end.z)])
	_shots.append([middle - facing * 40.0 + right * 30.0 + Vector3.UP * 35.0, middle - facing * 10.0])
	_camera.fov = 70.0
	_camera.far = 2500.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(_terrain.make_viewer())
	_show(0)


## The point at `p`'s x and z `above` metres over the ground.
func _on_ground(p: Vector3, above: float) -> Vector3:
	return Vector3(p.x, _terrain.ground_height(p.x, p.z) + above, p.z)


func _show(i: int) -> void:
	var shot: Array = _shots[i]
	var at: Vector3 = shot[0]
	var target: Vector3 = shot[1]
	_terrain.update_around([at, target.lerp(at, 0.5)], INF)
	_scenery.update_around([at, target.lerp(at, 0.5)], INF)
	_camera.global_position = at
	_camera.look_at(target)


func _process(_delta: float) -> void:
	if _shots.is_empty():
		return
	_ticks += 1
	if _ticks % SHOT_FRAMES == 1 and _ticks > 1:
		var i := _ticks / SHOT_FRAMES
		if i < _shots.size():
			_show(i)

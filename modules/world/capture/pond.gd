extends Node3D
## Capture setup: the first pond from its bank in the afternoon, then from above, then at
## a swimmer's eye height looking across it.

const WORLD := "res://modules/world/scenes/world.tscn"
## Frame -> [camera offset from the pond's middle, look offset from it].
const SHOTS := {
	1: [Vector3(16.0, 2.0, -6.0), Vector3(-4.0, -0.5, 2.0)],
	120: [Vector3(4.0, 26.0, 14.0), Vector3(0.0, 0.0, 0.0)],
	240: [Vector3(3.0, 0.5, 3.0), Vector3(-12.0, 0.3, -6.0)],
}

var _camera := Camera3D.new()
var _ticks := 0
var _middle := Vector3.ZERO
var _terrain: VoxelWorld


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_terrain = world.get_node("Terrain") as VoxelWorld
	var water := _terrain.heights.water
	var outline: PackedVector2Array = water.bodies[0]["outline"]
	var sum := Vector2.ZERO
	for p in outline:
		sum += p
	sum /= outline.size()
	_middle = Vector3(sum.x, water.level_of(0), sum.y)
	_camera.fov = 70.0
	_camera.far = 600.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(_terrain.make_viewer())
	_shot(SHOTS[1])
	(world.get_node("Scenery") as SceneryScatter).update_around([_middle], INF)
	_terrain.update_around([_middle], INF)


func _shot(s: Array) -> void:
	var from: Vector3 = _middle + (s[0] as Vector3)
	if not _terrain.heights.in_water(from.x, from.z):
		from.y = maxf(from.y, _terrain.ground_height(from.x, from.z) + 1.8)
	_camera.global_position = from
	_camera.look_at(_middle + (s[1] as Vector3))


func _process(_delta: float) -> void:
	if _terrain == null:
		return
	_ticks += 1
	if SHOTS.has(_ticks) and _ticks > 1:
		_shot(SHOTS[_ticks])

extends Node3D
## Capture setup: the pond nearest the camp from its bank in the afternoon, then from above,
## then at a swimmer's eye height looking across it.

const WORLD := "res://modules/world/scenes/world.tscn"
## Frame -> [camera offset from the shore, look offset from it], in the shore's frame: x along
## the shore, z out into the pond. From the shore rather than the pond's middle, as a
## generated pond can be hundreds of metres across.
const SHOTS := {
	1: [Vector3(2.0, 2.0, -6.0), Vector3(-3.0, -0.5, 14.0)],
	120: [Vector3(4.0, 26.0, -4.0), Vector3(0.0, 0.0, 16.0)],
	240: [Vector3(1.0, 0.5, 5.0), Vector3(-8.0, 0.3, 30.0)],
}

var _camera := Camera3D.new()
var _ticks := 0
var _shore := Transform3D.IDENTITY
var _terrain: VoxelWorld


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var terrain := world.get_node("Terrain") as VoxelWorld
	var shore := shore_of(terrain, VoxelWorld.spawn_of(world))
	if shore.is_empty():
		Log.info(&"capture", "%s: this map has no pond to film" % get_script().resource_path)
		get_tree().quit(0)
		return
	_terrain = terrain
	var inward := shore[1]
	_shore = Transform3D(Basis(Vector3.UP.cross(inward), Vector3.UP, inward), shore[0])
	_camera.fov = 70.0
	_camera.far = 600.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(_terrain.make_viewer())
	_shot(SHOTS[1])
	(world.get_node("Scenery") as SceneryScatter).update_around([shore[0]], INF)
	_terrain.update_around([shore[0]], INF)


func _shot(s: Array) -> void:
	var from: Vector3 = _shore * (s[0] as Vector3)
	if not _terrain.heights.in_water(from.x, from.z):
		from.y = maxf(from.y, _terrain.ground_height(from.x, from.z) + 1.8)
	_camera.global_position = from
	_camera.look_at(_shore * (s[1] as Vector3))


func _process(_delta: float) -> void:
	if _terrain == null:
		return
	_ticks += 1
	if SHOTS.has(_ticks) and _ticks > 1:
		_shot(SHOTS[_ticks])


## For the pond captures: [where the water of the pond nearest `at` begins on the side facing
## `at` (at the water's level), the way into the pond from there (on the ground plane)];
## empty when the map has no pond.
static func shore_of(terrain: VoxelWorld, at: Vector3) -> Array[Vector3]:
	var water := terrain.heights.water
	var near := Vector2(at.x, at.z)
	var pond := -1
	var best := INF
	for i in water.bodies.size():
		var d := (water.bodies[i]["box"] as Rect2).get_center().distance_to(near)
		if d < best:
			best = d
			pond = i
	if pond < 0:
		return []
	var outline: PackedVector2Array = water.bodies[pond]["outline"]
	var middle := Vector2.ZERO
	for p in outline:
		middle += p
	middle /= outline.size()
	var edge := outline[0]
	for p in outline:
		if p.distance_to(near) < edge.distance_to(near):
			edge = p
	var level := water.level_of(pond)
	var inward := (middle - edge).normalized()
	# The outline is grown past the water: walk in until the ground dips under the level.
	var shore := edge
	var reach := edge.distance_to(middle)
	var step := 0.0
	while step < reach and terrain.ground_height(shore.x, shore.y) >= level:
		step += 1.0
		shore = edge + inward * step
	return [Vector3(shore.x, level, shore.y), Vector3(inward.x, 0.0, inward.y)]

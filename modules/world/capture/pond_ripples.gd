extends Node3D
## Capture setup (trees hidden): from above the bank, rounds fired into the first pond every few frames (ripples
## and splashes), then a charge set off on the bank beside it at `BLAST_AT`: the crater dips
## under the pond's level and floods.

const WORLD := "res://modules/world/scenes/world.tscn"
const BLAST_AT := 150
const BLAST_RADIUS := 3.5

var _camera := Camera3D.new()
var _ticks := 0
var _middle := Vector3.ZERO
var _bank := Vector3.ZERO
var _terrain: VoxelWorld
var _rng := RandomNumberGenerator.new()


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
	# Just outside the edge nearest the camera.
	var from := _middle + Vector3(-2.0, 16.0, 15.0)
	var edge := outline[0]
	for p in outline:
		if p.distance_to(Vector2(from.x, from.z)) < edge.distance_to(Vector2(from.x, from.z)):
			edge = p
	var out := (edge - sum).normalized()
	var spot := edge + out * 2.5
	_bank = Vector3(spot.x, _terrain.ground_height(spot.x, spot.y), spot.y)
	_camera.fov = 70.0
	_camera.far = 600.0
	add_child(_camera)
	_camera.current = true
	# Behind the blast and above, looking over it at the pond.
	var back := Vector3(_bank.x - _middle.x, 0.0, _bank.z - _middle.z).normalized()
	from = _bank + back * 10.0 + Vector3.UP * 12.0
	_camera.global_position = from
	_camera.look_at(_bank.lerp(_middle, 0.4))
	_camera.add_child(_terrain.make_viewer())
	# The trees round this pond hide the bank from anywhere; this shot is about the water.
	(world.get_node("Scenery") as Node3D).visible = false
	_terrain.update_around([_middle], INF)
	_rng.seed = 5


func _process(_delta: float) -> void:
	if _terrain == null:
		return
	_ticks += 1
	if _ticks % 9 == 0 and _ticks < BLAST_AT + 100:
		var at := _middle + Vector3(_rng.randf_range(-6.0, 6.0), -1.5, _rng.randf_range(-5.0, 5.0))
		EventBus.publish(&"weapon.fired", {"from": _camera.global_position, "to": at})
	if _ticks == BLAST_AT:
		_terrain.server_dig(_bank, BLAST_RADIUS)
		EventBus.publish(&"explosion", {"position": _bank, "radius": BLAST_RADIUS})

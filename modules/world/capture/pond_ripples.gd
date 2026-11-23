extends Node3D
## Capture setup (trees hidden): from above the bank, rounds fired into the pond nearest the
## camp every few frames (ripples and splashes), then a charge set off on the bank beside it
## at `BLAST_AT`: the crater dips under the pond's level and floods.

const WORLD := "res://modules/world/scenes/world.tscn"
const Pond := preload("res://modules/world/capture/pond.gd")
const BLAST_AT := 150
const BLAST_RADIUS := 3.5

var _camera := Camera3D.new()
var _ticks := 0
var _water := Vector3.ZERO
var _bank := Vector3.ZERO
var _terrain: VoxelWorld
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var terrain := world.get_node("Terrain") as VoxelWorld
	var shore := Pond.shore_of(terrain, VoxelWorld.spawn_of(world))
	if shore.is_empty():
		Log.info(&"capture", "%s: this map has no pond to film" % get_script().resource_path)
		get_tree().quit(0)
		return
	_terrain = terrain
	var inward := shore[1]
	# Rounds land this far out from the shore: close enough to see, deep enough to splash.
	_water = shore[0] + inward * 12.0
	var spot := shore[0] - inward * 2.5
	_bank = Vector3(spot.x, _terrain.ground_height(spot.x, spot.z), spot.z)
	_camera.fov = 70.0
	_camera.far = 600.0
	add_child(_camera)
	_camera.current = true
	# Behind the blast and above, looking over it at the pond.
	_camera.global_position = _bank - inward * 10.0 + Vector3.UP * 12.0
	_camera.look_at(_bank.lerp(_water, 0.4))
	_camera.add_child(_terrain.make_viewer())
	# The trees round this pond hide the bank from anywhere; this shot is about the water.
	(world.get_node("Scenery") as Node3D).visible = false
	_terrain.update_around([_water], INF)
	_rng.seed = 5


func _process(_delta: float) -> void:
	if _terrain == null:
		return
	_ticks += 1
	if _ticks % 9 == 0 and _ticks < BLAST_AT + 100:
		var at := _water + Vector3(_rng.randf_range(-6.0, 6.0), -1.5, _rng.randf_range(-5.0, 5.0))
		EventBus.publish(&"weapon.fired", {"from": _camera.global_position, "to": at})
	if _ticks == BLAST_AT:
		_terrain.server_dig(_bank, BLAST_RADIUS)
		EventBus.publish(&"explosion", {"position": _bank, "radius": BLAST_RADIUS})


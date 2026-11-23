extends Node3D
## Capture setup: a slow pan across the world from a low hill, for judging terrain,
## scenery and lighting.

const WORLD := "res://modules/world/scenes/world.tscn"

var _camera := Camera3D.new()
var _t := 0.0
var _at := Vector3.ZERO


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	_at = VoxelWorld.spawn_of(world, Vector3(0.0, 4.0, 20.0))
	add_child(_camera)
	_camera.fov = 75.0
	_camera.current = true


func _process(delta: float) -> void:
	_t += delta
	var yaw := deg_to_rad(-30.0 + _t * 12.0)
	_camera.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-8.0), yaw, 0.0)), _at)

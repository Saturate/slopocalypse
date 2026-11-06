extends Node3D
## Capture setup: a slow pan across the world from a low hill, for judging terrain,
## scenery and lighting.

const WORLD := "res://modules/world/scenes/world.tscn"

var _camera := Camera3D.new()
var _t := 0.0


func _ready() -> void:
	# Voxel terrain streams in; wait for the spawn area before dropping anything onto it.
	await VoxelWorld.add_and_wait(self, WORLD)
	add_child(_camera)
	_camera.fov = 75.0
	_camera.current = true


func _process(delta: float) -> void:
	_t += delta
	var yaw := deg_to_rad(-30.0 + _t * 12.0)
	_camera.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-8.0), yaw, 0.0)), Vector3(0.0, 4.0, 20.0))

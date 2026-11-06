extends Node3D
## Capture setup: the whole map from above, for judging biome layout (forests, meadows,
## dry and rocky ground). Doubles as the map preview for the generated-map work (#32).
## Fog is switched off and the camera kept within tree draw distance so the layout reads.

const WORLD := "res://modules/world/scenes/world.tscn"

var _camera := Camera3D.new()


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var env: WorldEnvironment = world.get_node("Environment")
	env.environment = env.environment.duplicate()
	env.environment.fog_enabled = false
	env.environment.volumetric_fog_enabled = false
	add_child(_camera)
	_camera.current = true
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 260.0
	_camera.far = 400.0
	_camera.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0.0, 0.0)), Vector3(0, 150, 0))

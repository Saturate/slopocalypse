extends Node3D
## Capture setup: the perf overlay (F3) over the world, after a few samples.

const WORLD := "res://modules/world/scenes/world.tscn"

var _camera := Camera3D.new()


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var voxels: VoxelWorld = world.get_node("Terrain")
	_camera.far = 900.0
	add_child(_camera)
	_camera.current = true
	_camera.add_child(voxels.make_viewer())
	# Behind the spot, looking on down the highway.
	_camera.global_position = voxels.road_point(30.0) + Vector3.UP * 3.0
	_camera.look_at(voxels.road_point(70.0) + Vector3.UP)
	Performance.add_custom_monitor(&"capture/example", func() -> int: return 7)
	var perf: Node = (load("res://modules/perf/perf_module.gd") as GDScript).new()
	perf.set(&"log_dir", "user://perf-capture")
	add_child(perf)
	(perf.get_node("Overlay") as CanvasLayer).visible = true


func _exit_tree() -> void:
	Performance.remove_custom_monitor(&"capture/example")

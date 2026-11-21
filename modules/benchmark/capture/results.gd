extends Node3D
## Capture setup: the benchmark's results screen over the world, with typical numbers and a
## few hitches, as a player sees it at the end of a run.

const WORLD := "res://modules/world/scenes/world.tscn"


func _ready() -> void:
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = VoxelWorld.spawn_of(world, Vector3(0.0, 2.0, 6.0))
	camera.look_at(VoxelWorld.spawn_of(world, Vector3(0.0, 1.0, 0.0)))
	camera.current = true
	var frames := PackedFloat32Array()
	for i in 3000:
		frames.append(16.0 + float(i % 7))
	for i in 30:
		frames.append(48.0 + float(i))
	frames.append(148.7)
	frames.append(84.3)
	var results := BenchmarkStats.summarise(frames)
	results["seconds"] = 60.0
	results["draw_calls"] = 9200.0
	results["objects_drawn"] = 11800.0
	results["gpu_ms"] = 11.4
	results["render_cpu_ms"] = 5.2
	results["hitches"] = [
		{"t": 31.2, "ms": 148.7, "zones": {"world/scenery_build": 120.1, "net/smoothing": 1.8}, "compiles": {}},
		{"t": 44.0, "ms": 84.3, "zones": {"event/explosion/audio": 10.6, "event/smoke.spawned/smoke": 11.4}, "compiles": {"draw": 2.0}},
		{"t": 52.5, "ms": 77.0, "zones": {}, "compiles": {}},
	]
	var screen := BenchmarkResults.new()
	add_child(screen)
	screen.show_results(results, true)

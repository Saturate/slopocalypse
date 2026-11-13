extends Node3D
## Capture setup and measurement (#306): 20 apartment blocks at 0.10 m voxels, first all
## drawn as meshes, then all drawn as GPU voxel volumes, from the same street-level camera.
## Prints the GPU and CPU frame time of each, averaged over `FRAMES` after a warm-up, and how
## long the model took to mesh and to upload. On a real GPU these are the numbers that count;
## a software renderer only shows whether it works. Capture it with `--frames 168 --sheet 4`:
## the first frame shows the meshes, the last three the volumes.

const VALUES := {"floors": 4.0, "stairwells": 2.0, "voxel": 0.1, "seed": 3.0}
const GRID := Vector2i(5, 4)
const SPACING := Vector2(36.0, 24.0)
const WARM := 20
const FRAMES := 60

var _blocks: Array[Node3D] = []
var _mesh: ArrayMesh
var _model: VoxelModel
var _phase := 0
var _ticks := 0
var _gpu := 0.0
var _cpu := 0.0
var _results: Array[String] = []


func _ready() -> void:
	var t := Time.get_ticks_usec()
	_model = VoxApartment.new().build(VALUES)
	var built := Time.get_ticks_usec()
	_mesh = VoxGenerator.to_mesh(_model)
	var meshed := Time.get_ticks_usec()
	var probe := VoxelVolume.new()
	probe.model = _model
	probe.refresh()
	var uploaded := Time.get_ticks_usec()
	var bytes := probe.gpu_bytes
	probe.free()
	var dense := _model.cells().x * _model.cells().y * _model.cells().z * 4
	_results.append("model: %d voxels, built in %d ms; mesh %d faces in %d ms; volume upload %d ms (%.1f MB on the GPU, a dense grid would be %.1f MB)" % [
		_model.voxel_count(), (built - t) / 1000, _mesh.surface_get_array_len(0) / 4, (meshed - built) / 1000,
		(uploaded - meshed) / 1000, bytes / 1048576.0, dense / 1048576.0])
	_scene()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_show(false)


func _process(_delta: float) -> void:
	_ticks += 1
	if _ticks <= WARM:
		return
	var vp := get_viewport().get_viewport_rid()
	_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
	if _ticks < WARM + FRAMES:
		return
	_results.append("%s: GPU %.2f ms, render CPU %.2f ms a frame" % ["volumes" if _phase == 1 else "meshes", _gpu / FRAMES, _cpu / FRAMES])
	_gpu = 0.0
	_cpu = 0.0
	_ticks = 0
	_phase += 1
	if _phase == 1:
		_show(true)
	else:
		for line in _results:
			print("volume_bench: " + line)
		set_process(false)


## Every block as a mesh, or every block as a volume.
func _show(volumes: bool) -> void:
	for b in _blocks:
		b.queue_free()
	_blocks.clear()
	for i in GRID.x:
		for j in GRID.y:
			var at := Vector3((i - (GRID.x - 1) / 2.0) * SPACING.x, 0.0, (j - (GRID.y - 1) / 2.0) * SPACING.y)
			var node: Node3D
			if volumes:
				var v := VoxelVolume.new()
				v.model = _model
				node = v
				add_child(v)
				v.refresh()
			else:
				var m := MeshInstance3D.new()
				m.mesh = _mesh
				node = m
				add_child(m)
			node.position = at
			_blocks.append(node)


func _scene() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	ground.mesh = plane
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.36, 0.42, 0.25)
	ground.material_override = green
	add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	sun.transform = Transform3D(Basis.from_euler(Vector3(-0.8, 0.6, 0.0)), Vector3.ZERO)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.8, 0.84, 0.88)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	add_child(env)
	var camera := Camera3D.new()
	camera.fov = 70.0
	camera.far = 600.0
	add_child(camera)
	camera.current = true
	camera.transform = Transform3D(Basis.IDENTITY, Vector3(-60.0, 6.0, -70.0)).looking_at(Vector3(0.0, 6.0, 0.0))

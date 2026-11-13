extends Node3D
## Capture setup (#306): the same apartment block at 0.10 m voxels drawn as a mesh (left) and
## on the GPU as a voxel volume (right), with a plain box pushed into the volume to check
## depth sorting, and a sun for shadows. The camera circles once.

const VALUES := {"floors": 3.0, "stairwells": 1.0, "voxel": 0.1, "seed": 4.0}
const SPACING := 20.0

var _camera: Camera3D
var _ticks := 0


func _ready() -> void:
	var model := VoxApartment.new().build(VALUES)
	var mesh := MeshInstance3D.new()
	mesh.mesh = VoxGenerator.to_mesh(model)
	mesh.position.x = -SPACING / 2.0
	add_child(mesh)
	var volume := VoxelVolume.new()
	volume.model = model
	volume.position.x = SPACING / 2.0
	add_child(volume)
	volume.refresh()
	var probe := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	probe.mesh = box
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.15, 0.1)
	probe.material_override = red
	probe.position = Vector3(SPACING / 2.0 - 4.0, 1.0, -5.5)
	add_child(probe)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.36, 0.42, 0.25)
	ground.material_override = green
	ground.position.y = -0.01
	add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.transform = Transform3D(Basis.from_euler(Vector3(-0.8, 0.6, 0.0)), Vector3.ZERO)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.8, 0.84, 0.88)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	add_child(_camera)
	_camera.current = true
	_place(0.0)


func _process(_delta: float) -> void:
	_ticks += 1
	_place(_ticks / 60.0 * TAU)


func _place(angle: float) -> void:
	var at := Vector3(sin(angle + PI + 0.4) * 34.0, 11.0, cos(angle + PI + 0.4) * 34.0)
	_camera.transform = Transform3D(Basis.IDENTITY, at).looking_at(Vector3(0.0, 4.0, 0.0))

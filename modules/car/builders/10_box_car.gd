extends SceneTree
## Builds modules/car/scenes/box_car.tscn from car.json: body, four wheels, exit point,
## chase camera, intent component.

const OUT := "res://modules/car/scenes/box_car.tscn"
const CONFIG := "res://modules/car/data/car.json"


func _initialize() -> void:
	var c: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if not c is Dictionary:
		push_error("%s: could not parse" % CONFIG)
		quit(1)
		return
	var cfg: Dictionary = c
	var body_size := Vector3(cfg["body_size"][0], cfg["body_size"][1], cfg["body_size"][2])
	var body_height: float = cfg["body_height"]

	var root := VehicleBody3D.new()
	root.name = "BoxCar"
	root.mass = cfg["mass"]
	# A low centre of mass keeps an arcade car from rolling in corners.
	root.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	root.center_of_mass = Vector3(0.0, 0.2, 0.0)

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = body_size
	shape.shape = box
	shape.position = Vector3(0.0, body_height, 0.0)
	root.add_child(shape)

	var mesh := MeshInstance3D.new()
	mesh.name = "BodyMesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = body_size
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.7, 0.32, 0.18)
	box_mesh.material = paint
	mesh.mesh = box_mesh
	mesh.position = shape.position
	root.add_child(mesh)

	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.12, 0.12, 0.12)
	var wx: float = cfg["wheel_x"]
	var wz: float = cfg["wheel_z"]
	# VehicleBody3D drives along +Z, so the nose (and the steering wheels) are at +Z.
	# Facing +Z, the car's left is +X.
	for spec in [["WheelFL", wx, wz, true], ["WheelFR", -wx, wz, true], ["WheelRL", wx, -wz, false], ["WheelRR", -wx, -wz, false]]:
		root.add_child(_wheel(spec[0], Vector3(spec[1], cfg["wheel_y"], spec[2]), spec[3], cfg, wheel_mat))

	var exit_point := Marker3D.new()
	exit_point.name = "ExitPoint"
	exit_point.position = Vector3(body_size.x / 2.0 + 1.0, 0.0, 0.0)
	root.add_child(exit_point)

	var camera := Camera3D.new()
	camera.name = "ChaseCamera"
	camera.fov = 75.0
	# Behind the car (-Z), turned round to look along +Z, tilted down a little.
	camera.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-15.0), PI, 0.0)), Vector3(0.0, 3.0, -7.5))
	root.add_child(camera)

	var intent := Node.new()
	intent.name = "Intent"
	intent.set_script(load("res://modules/car/scripts/car_intent.gd"))
	root.add_child(intent)

	root.set_script(load("res://modules/car/scripts/car_controller.gd"))
	root.set("intent_path", NodePath("Intent"))
	root.set("exit_point_path", NodePath("ExitPoint"))
	root.set("camera_path", NodePath("ChaseCamera"))

	var result := SceneBuilder.pack_and_save(root, OUT)
	root.free()
	if result.error != OK:
		push_error(result.message)
		quit(1)
		return
	quit(0)


func _wheel(wheel_name: String, pos: Vector3, front: bool, cfg: Dictionary, mat: Material) -> VehicleWheel3D:
	var wheel := VehicleWheel3D.new()
	wheel.name = wheel_name
	wheel.position = pos
	wheel.use_as_steering = front
	wheel.use_as_traction = not front
	wheel.wheel_radius = cfg["wheel_radius"]
	wheel.wheel_rest_length = cfg["suspension_rest_length"]
	wheel.suspension_travel = cfg["suspension_travel"]
	wheel.suspension_stiffness = cfg["suspension_stiffness"]
	wheel.suspension_max_force = cfg["suspension_max_force"]
	wheel.damping_compression = cfg["damping_compression"]
	wheel.damping_relaxation = cfg["damping_relaxation"]
	wheel.wheel_friction_slip = cfg["friction_slip"]
	wheel.wheel_roll_influence = cfg["roll_influence"]
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var cyl := CylinderMesh.new()
	cyl.top_radius = cfg["wheel_radius"]
	cyl.bottom_radius = cfg["wheel_radius"]
	cyl.height = cfg["wheel_width"]
	cyl.material = mat
	mesh.mesh = cyl
	# Cylinders stand on Y; lay it on its side so it rolls around X.
	mesh.rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))
	wheel.add_child(mesh)
	return wheel

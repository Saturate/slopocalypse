extends SceneTree
## Builds modules/car/scenes/box_car.tscn from car.json: collision, voxel looks (made at
## runtime), four wheels, a door each side, chase camera, intent component.

const OUT := "res://modules/car/scenes/box_car.tscn"
const CONFIG := "res://modules/car/data/car.json"
## How far the suspension sits down under the car's own weight.
const GROUND_SAG := 0.05


func _initialize() -> void:
	var c: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if not c is Dictionary:
		push_error("%s: could not parse" % CONFIG)
		quit(1)
		return
	var cfg: Dictionary = c
	var length: float = cfg["length"]
	var width: float = cfg["width"]
	# Where the ground is under the car at rest, in the car's frame: the voxel looks are
	# built standing on it.
	var ground_y: float = float(cfg["wheel_y"]) - float(cfg["suspension_rest_length"]) - float(cfg["wheel_radius"]) + GROUND_SAG

	var root := VehicleBody3D.new()
	root.name = "BoxCar"
	root.mass = cfg["mass"]
	# A low centre of mass keeps an arcade car from rolling in corners.
	root.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	root.center_of_mass = Vector3(0.0, ground_y + 0.45, 0.0)

	# Two boxes: the body tub and the cab on it (VoxCar's sill, belt and roof heights).
	_box(root, "Shape", Vector3(width, VoxCar.BELT - VoxCar.SILL, length), Vector3(0.0, ground_y + (VoxCar.SILL + VoxCar.BELT) / 2.0, 0.0))
	var cab_front := length / 2.0 - 1.25
	var cab_len := 1.55
	_box(root, "CabShape", Vector3(width - 0.12, VoxCar.ROOF - VoxCar.BELT, cab_len), Vector3(0.0, ground_y + (VoxCar.BELT + VoxCar.ROOF) / 2.0, cab_front - cab_len / 2.0))

	# The voxel body and wheels are made at runtime on clients (CarLooks), not saved here.
	var looks := Node3D.new()
	looks.name = "Looks"
	looks.position = Vector3(0.0, ground_y, 0.0)
	looks.set_script(load("res://modules/car/scripts/car_looks.gd"))
	root.add_child(looks)

	var wx: float = cfg["wheel_x"]
	var wz: float = cfg["wheel_z"]
	# VehicleBody3D drives along +Z, so the nose (and the steering wheels) are at +Z.
	# Facing +Z, the car's left is +X.
	for spec in [["WheelFL", wx, wz, true], ["WheelFR", -wx, wz, true], ["WheelRL", wx, -wz, false], ["WheelRR", -wx, -wz, false]]:
		root.add_child(_wheel(spec[0], Vector3(spec[1], cfg["wheel_y"], spec[2]), spec[3], cfg))

	# Doors: the driver sits on the left (+X), the passenger on the right.
	var exit_point := Marker3D.new()
	exit_point.name = "ExitPoint"
	exit_point.position = Vector3(width / 2.0 + 0.9, 0.0, cab_front - cab_len / 2.0)
	root.add_child(exit_point)
	var passenger_exit := Marker3D.new()
	passenger_exit.name = "PassengerExit"
	passenger_exit.position = Vector3(-width / 2.0 - 0.9, 0.0, cab_front - cab_len / 2.0)
	root.add_child(passenger_exit)

	# Follows the car on its own (top level), smoothed; CarCamera places it every frame.
	var camera := Camera3D.new()
	camera.name = "ChaseCamera"
	camera.fov = 75.0
	camera.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-15.0), PI, 0.0)), Vector3(0.0, 3.0, -7.5))
	camera.set_script(load("res://modules/car/scripts/car_camera.gd"))
	root.add_child(camera)

	var intent := Node.new()
	intent.name = "Intent"
	intent.set_script(load("res://modules/car/scripts/car_intent.gd"))
	root.add_child(intent)

	root.set_script(load("res://modules/car/scripts/car_controller.gd"))
	root.set("intent_path", NodePath("Intent"))
	root.set("exit_point_path", NodePath("ExitPoint"))
	root.set("passenger_exit_path", NodePath("PassengerExit"))
	root.set("camera_path", NodePath("ChaseCamera"))
	# The server simulates the car; clients see it move.
	root.add_child(NetSync.make([".:position", ".:rotation"]))

	var result := SceneBuilder.pack_and_save(root, OUT)
	root.free()
	if result.error != OK:
		push_error(result.message)
		quit(1)
		return
	quit(0)


func _box(root: Node3D, shape_name: String, size: Vector3, at: Vector3) -> void:
	var shape := CollisionShape3D.new()
	shape.name = shape_name
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	root.add_child(shape)


func _wheel(wheel_name: String, pos: Vector3, front: bool, cfg: Dictionary) -> VehicleWheel3D:
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
	# Filled with a voxel wheel by CarLooks on clients.
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	wheel.add_child(mesh)
	return wheel

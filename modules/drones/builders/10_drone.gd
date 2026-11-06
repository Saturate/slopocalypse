extends SceneTree
## Builds modules/drones/scenes/drone.tscn: a low-poly quadcopter (body, four arms, rotors,
## camera pod, warning light) with collision, health and the stalker script.

const OUT := "res://modules/drones/scenes/drone.tscn"
const CONFIG := "res://modules/drones/data/drones.json"

const SHELL := Color(0.24, 0.25, 0.23)
const DARK := Color(0.09, 0.09, 0.1)
const ACCENT := Color(0.62, 0.5, 0.2)


func _initialize() -> void:
	var cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if not cfg is Dictionary:
		push_error("%s: could not parse" % CONFIG)
		quit(1)
		return

	var root := CharacterBody3D.new()
	root.name = "Drone"
	root.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING

	var st := LowPoly.begin()
	LowPoly.chamfer_box(st, Vector3(0.36, 0.12, 0.46), 0.03, Transform3D.IDENTITY, SHELL)
	LowPoly.chamfer_box(st, Vector3(0.22, 0.06, 0.28), 0.015, Transform3D(Basis.IDENTITY, Vector3(0, 0.08, 0)), ACCENT)
	LowPoly.chamfer_box(st, Vector3(0.12, 0.1, 0.12), 0.02, Transform3D(Basis.IDENTITY, Vector3(0, -0.1, -0.14)), DARK)
	for corner: Vector3 in [Vector3(0.36, 0, 0.36), Vector3(-0.36, 0, 0.36), Vector3(0.36, 0, -0.36), Vector3(-0.36, 0, -0.36)]:
		var arm_basis := Basis.looking_at(corner.normalized(), Vector3.UP)
		LowPoly.chamfer_box(st, Vector3(0.05, 0.04, corner.length()), 0.01, Transform3D(arm_basis, corner * 0.5), DARK)
		LowPoly.cylinder(st, 0.045, 0.08, 8, Transform3D(Basis.IDENTITY, corner + Vector3(0, 0.04, 0)), DARK)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = LowPoly.finish(st, LowPoly.material(0.6, 0.3))
	root.add_child(body)

	# Rotor discs spin on the client; kept as separate nodes so they can rotate.
	var rotors := Node3D.new()
	rotors.name = "Rotors"
	root.add_child(rotors)
	var rotor_mat := StandardMaterial3D.new()
	rotor_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.45)
	rotor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var i := 0
	for corner: Vector3 in [Vector3(0.36, 0.09, 0.36), Vector3(-0.36, 0.09, 0.36), Vector3(0.36, 0.09, -0.36), Vector3(-0.36, 0.09, -0.36)]:
		var rotor := MeshInstance3D.new()
		rotor.name = "Rotor%d" % i
		var disc := CylinderMesh.new()
		disc.top_radius = 0.2
		disc.bottom_radius = 0.2
		disc.height = 0.01
		disc.radial_segments = 12
		disc.material = rotor_mat
		rotor.mesh = disc
		rotor.position = corner
		rotors.add_child(rotor)
		i += 1

	var light := OmniLight3D.new()
	light.name = "WarningLight"
	light.light_color = Color(1.0, 0.1, 0.05)
	light.omni_range = 3.0
	light.position = Vector3(0, -0.05, -0.24)
	root.add_child(light)

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	# A bit larger than the body so it is fair to hit at range.
	box.size = Vector3(0.95, 0.3, 0.95)
	shape.shape = box
	root.add_child(shape)

	var health := Node.new()
	health.name = "Health"
	health.set_script(load("res://core/components/health_component.gd"))
	health.set("max_health", cfg["max_health"])
	root.add_child(health)

	root.set_script(load("res://modules/drones/scripts/stalker_drone.gd"))
	root.set("health_path", NodePath("Health"))
	root.set("rotors_path", NodePath("Rotors"))
	root.set("light_path", NodePath("WarningLight"))

	var result := SceneBuilder.pack_and_save(root, OUT)
	root.free()
	if result.error != OK:
		push_error(result.message)
		quit(1)
		return
	quit(0)

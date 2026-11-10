class_name TransportCar
extends StaticBody3D
## The car that takes the group out to a mission and back: parked in the home tunnel, and
## waiting at the drop-off point while a mission runs. Nobody drives it yet; F rides. A
## solid, boxy off-roader so it reads as a vehicle and gives cover.

const BODY := Vector3(2.0, 0.9, 4.4)
const CAB := Vector3(1.8, 0.75, 2.1)
const WHEEL_RADIUS := 0.42
const WHEEL_WIDTH := 0.3
const PAINT := Color(0.32, 0.36, 0.26)
const GLASS := Color(0.16, 0.2, 0.24)
const TYRE := Color(0.08, 0.08, 0.08)
const LAMP_COLOUR := Color(1.0, 0.86, 0.6)
const LAMP_ENERGY := 1.4
const LAMP_RANGE := 6.0


func _ready() -> void:
	add_to_group(&"transport_cars")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(BODY.x, BODY.y + CAB.y, BODY.z)
	shape.shape = box
	shape.position.y = WHEEL_RADIUS + (BODY.y + CAB.y) / 2.0
	add_child(shape)
	_box(BODY, Vector3(0.0, WHEEL_RADIUS + BODY.y / 2.0, 0.0), PAINT)
	_box(CAB, Vector3(0.0, WHEEL_RADIUS + BODY.y + CAB.y / 2.0, -0.4), PAINT.darkened(0.1))
	# Windows: a darker band round the cab.
	_box(Vector3(CAB.x + 0.02, CAB.y * 0.5, CAB.z - 0.3), Vector3(0.0, WHEEL_RADIUS + BODY.y + CAB.y * 0.55, -0.4), GLASS)
	_box(Vector3(CAB.x - 0.3, CAB.y * 0.5, CAB.z + 0.02), Vector3(0.0, WHEEL_RADIUS + BODY.y + CAB.y * 0.55, -0.4), GLASS)
	for x: float in [-BODY.x / 2.0, BODY.x / 2.0]:
		for z: float in [-BODY.z * 0.33, BODY.z * 0.33]:
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = WHEEL_RADIUS
			cyl.bottom_radius = WHEEL_RADIUS
			cyl.height = WHEEL_WIDTH
			cyl.material = _mat(TYRE)
			wheel.mesh = cyl
			wheel.rotation.z = PI / 2.0
			wheel.position = Vector3(x, WHEEL_RADIUS, z)
			add_child(wheel)
	var label := Label3D.new()
	label.text = "Transport"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.003
	label.outline_size = 10
	label.position.y = WHEEL_RADIUS + BODY.y + CAB.y + 0.4
	label.visibility_range_end = 12.0
	add_child(label)
	# Lit from above so it stands out in the tunnel's gloom (and at night on the road).
	var lamp := OmniLight3D.new()
	lamp.light_color = LAMP_COLOUR
	lamp.light_energy = LAMP_ENERGY
	lamp.omni_range = LAMP_RANGE
	lamp.position.y = WHEEL_RADIUS + BODY.y + CAB.y + 1.2
	add_child(lamp)


func _box(size: Vector3, at: Vector3, colour: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _mat(colour)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	add_child(node)


static func _mat(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.85
	return mat

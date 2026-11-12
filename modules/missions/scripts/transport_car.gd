class_name TransportCar
extends StaticBody3D
## The car that takes the group out to a mission and back: parked in the home tunnel, and
## waiting at the drop-off point while a mission runs. Nobody drives it yet; F rides. The voxel
## kit's car (`VoxCar`), sized as a bigger off-roader in army green with a roof rack, on voxel
## wheels; solid, so it gives cover. The server builds no meshes, only its collision.

## The car's look, as `VoxCar` parameters.
const LOOK := {"seed": 7, "paint": 1, "length": 4.8, "width": 2.15, "wheel_x": 0.9, "wheel_z": 1.6, "wheel_radius": 0.45, "wear": 0.6, "rack": 1, "voxel": 0.08}
const WHEEL_WIDTH := 0.32
const LAMP_COLOUR := Color(1.0, 0.86, 0.6)
const LAMP_ENERGY := 1.4
const LAMP_RANGE := 6.0

## Built once per run and shared by every transport.
static var _body: ArrayMesh
static var _wheel: ArrayMesh


func _ready() -> void:
	add_to_group(&"transport_cars")
	var length := float(LOOK["length"])
	var width := float(LOOK["width"])
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, VoxCar.ROOF, length)
	shape.shape = box
	shape.position.y = VoxCar.ROOF / 2.0
	add_child(shape)
	if DisplayServer.get_name() != "headless":
		_build_looks()
	var top := VoxCar.ROOF
	var label := Label3D.new()
	label.text = "Transport"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.003
	label.outline_size = 10
	label.position.y = top + 0.4
	label.visibility_range_end = 12.0
	add_child(label)
	# Lit from above so it stands out in the tunnel's gloom (and at night on the road).
	var lamp := OmniLight3D.new()
	lamp.light_color = LAMP_COLOUR
	lamp.light_energy = LAMP_ENERGY
	lamp.omni_range = LAMP_RANGE
	lamp.position.y = top + 1.2
	add_child(lamp)


## The voxel body and a voxel wheel at each corner, laid on its axle with the hub outwards.
func _build_looks() -> void:
	if _body == null:
		_body = VoxGenerator.to_mesh(VoxCar.new().build(LOOK))
		_wheel = VoxGenerator.to_mesh(VoxCar.wheel(float(LOOK["wheel_radius"]), WHEEL_WIDTH))
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _body
	add_child(body)
	var r := float(LOOK["wheel_radius"])
	for x: float in [-float(LOOK["wheel_x"]), float(LOOK["wheel_x"])]:
		for z: float in [-float(LOOK["wheel_z"]), float(LOOK["wheel_z"])]:
			var hub := Node3D.new()
			hub.position = Vector3(x, r, z)
			add_child(hub)
			var mesh := MeshInstance3D.new()
			mesh.mesh = _wheel
			var outward := signf(x)
			mesh.transform = Transform3D(Basis(Vector3.BACK, -outward * PI / 2.0), Vector3(-outward * WHEEL_WIDTH / 2.0, 0.0, 0.0))
			hub.add_child(mesh)

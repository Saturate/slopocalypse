extends Node3D
## Client-only looks: puts the voxel body (VoxCar) here and a voxel wheel on each wheel, made
## from car.json when the car appears. The server never builds meshes. No class_name and no
## autoloads, so the scene builder can attach it.

const CONFIG := "res://modules/car/data/car.json"

## Generated once per run and shared by every car.
static var _body: ArrayMesh
static var _wheel: ArrayMesh


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if not cfg is Dictionary:
		return
	var c: Dictionary = cfg
	if _body == null:
		var looks: Dictionary = c.get("looks", {})
		var values := {
			"seed": looks.get("seed", 1.0),
			"paint": looks.get("paint", 0.0),
			"wear": looks.get("wear", 0.5),
			"length": c["length"],
			"width": c["width"],
			"wheel_x": c["wheel_x"],
			"wheel_z": c["wheel_z"],
			"wheel_radius": c["wheel_radius"],
		}
		_body = VoxGenerator.to_mesh(VoxCar.new().build(values))
		_wheel = VoxGenerator.to_mesh(VoxCar.wheel(float(c["wheel_radius"]), float(c["wheel_width"])))
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _body
	add_child(body)
	var width: float = c["wheel_width"]
	for child in get_parent().get_children():
		if child is VehicleWheel3D:
			var mesh := child.get_node_or_null("Mesh") as MeshInstance3D
			if mesh == null:
				continue
			mesh.mesh = _wheel
			# The wheel is built standing on y from its base; lay it on its axle (x), centred,
			# with the hub facing outwards on each side.
			var outward := signf(child.position.x)
			mesh.transform = Transform3D(Basis(Vector3.BACK, -outward * PI / 2.0), Vector3(-outward * width / 2.0, 0.0, 0.0))

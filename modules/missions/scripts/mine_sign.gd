class_name MineSign
extends Node3D
## A hand-painted warning on a stake at the edge of a minefield.

const POST := Color(0.36, 0.27, 0.18)
const BOARD := Color(0.78, 0.7, 0.5)


func _ready() -> void:
	add_to_group(&"mine_signs")
	if DisplayServer.get_name() == "headless":
		return
	_box(Vector3(0.08, 1.4, 0.08), Vector3(0, 0.7, 0), POST)
	_box(Vector3(0.7, 0.4, 0.04), Vector3(0, 1.25, 0), BOARD)
	for face: float in [0.0, PI]:
		var label := Label3D.new()
		label.text = "MINES"
		label.font_size = 48
		label.pixel_size = 0.004
		label.modulate = Color(0.7, 0.1, 0.08)
		label.outline_size = 0
		label.position = Vector3(0, 1.25, 0.025 if face == 0.0 else -0.025)
		label.rotation.y = face
		add_child(label)


func _box(size: Vector3, at: Vector3, colour: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.9
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	add_child(node)

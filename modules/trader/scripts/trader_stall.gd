class_name TraderStall
extends StaticBody3D
## The trader's stall in the home tunnel: a plank counter with crates and a hanging sign.
## Faces along its local -Z.

const COUNTER := Vector3(2.4, 1.0, 0.7)
const WOOD := Color(0.42, 0.31, 0.2)
const TOP := Color(0.32, 0.24, 0.16)
const CRATE := Color(0.3, 0.36, 0.24)
const SIGN := Color(0.15, 0.14, 0.12)
const LAMP_COLOUR := Color(1.0, 0.85, 0.55)


func _ready() -> void:
	add_to_group(&"trader_stalls")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = COUNTER
	shape.shape = box
	shape.position.y = COUNTER.y / 2.0
	add_child(shape)
	_box(COUNTER, Vector3(0, COUNTER.y / 2.0, 0), WOOD)
	_box(Vector3(COUNTER.x + 0.1, 0.06, COUNTER.z + 0.1), Vector3(0, COUNTER.y + 0.03, 0), TOP)
	# Wares on the counter and crates behind it.
	_box(Vector3(0.5, 0.35, 0.4), Vector3(-0.7, COUNTER.y + 0.24, 0.05), CRATE)
	_box(Vector3(0.3, 0.2, 0.25), Vector3(0.6, COUNTER.y + 0.16, -0.05), CRATE.lightened(0.2))
	_box(Vector3(0.7, 0.6, 0.6), Vector3(0.5, 0.3, 0.9), CRATE)
	_box(Vector3(0.6, 0.5, 0.6), Vector3(-0.6, 0.25, 1.0), CRATE.darkened(0.15))
	_box(Vector3(1.6, 0.4, 0.05), Vector3(0, 2.4, 0), SIGN)
	var label := Label3D.new()
	label.text = "TRADER"
	label.font_size = 64
	label.pixel_size = 0.004
	label.outline_size = 10
	label.modulate = Color(1.0, 0.82, 0.45)
	label.position = Vector3(0, 2.4, -0.04)
	label.rotation.y = PI
	add_child(label)
	var lamp := OmniLight3D.new()
	lamp.light_color = LAMP_COLOUR
	lamp.light_energy = 1.2
	lamp.omni_range = 5.0
	lamp.position = Vector3(0, 2.2, -0.6)
	add_child(lamp)


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

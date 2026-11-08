class_name LootCrate
extends StaticBody3D
## A supply crate somewhere on the map. Searching it (F) moves what it holds into the
## searcher's backpack as far as it fits; the server keeps the contents and refills an
## empty crate after a while. Solid, so it is also something to hide behind.

const SIZE := Vector3(0.9, 0.6, 0.6)
const FULL := Color(0.3, 0.36, 0.24)
const EMPTY := Color(0.2, 0.21, 0.19)

var _lid: MeshInstance3D
var _label: Label3D
var _body_mat := StandardMaterial3D.new()


func _ready() -> void:
	add_to_group(&"crates")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE
	shape.shape = box
	shape.position.y = SIZE.y / 2.0
	add_child(shape)
	_body_mat.albedo_color = FULL
	_body_mat.roughness = 0.85
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = SIZE
	mesh.material = _body_mat
	body.mesh = mesh
	body.position.y = SIZE.y / 2.0
	add_child(body)
	# Darker bands and a lid read as a military crate rather than a plain box.
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = Color(0.12, 0.13, 0.11)
	for x in [-0.3, 0.3]:
		var band := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.06, SIZE.y + 0.01, SIZE.z + 0.01)
		b.material = band_mat
		band.mesh = b
		band.position = Vector3(x, SIZE.y / 2.0, 0.0)
		add_child(band)
	_lid = MeshInstance3D.new()
	var lid := BoxMesh.new()
	lid.size = Vector3(SIZE.x + 0.04, 0.05, SIZE.z + 0.04)
	lid.material = band_mat
	_lid.mesh = lid
	_lid.position.y = SIZE.y + 0.025
	add_child(_lid)
	_label = Label3D.new()
	_label.text = "Crate"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.pixel_size = 0.002
	_label.outline_size = 10
	_label.position.y = SIZE.y + 0.3
	_label.visibility_range_end = 6.0
	add_child(_label)


## Shown everywhere when the server says the crate was emptied or refilled.
func set_empty(empty: bool) -> void:
	set_meta(&"empty", empty)
	_body_mat.albedo_color = EMPTY if empty else FULL
	# An emptied crate has its lid pushed aside.
	_lid.position = Vector3(0.25, SIZE.y + 0.025, 0.12) if empty else Vector3(0.0, SIZE.y + 0.025, 0.0)
	_lid.rotation.y = 0.5 if empty else 0.0
	_label.text = "Empty" if empty else "Crate"

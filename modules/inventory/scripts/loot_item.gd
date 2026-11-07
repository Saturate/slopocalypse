class_name LootItem
extends Node3D
## An item lying on the ground. Created by the server and, through the inventory module's
## spawner, on every client. Shows a plain box sized like the item in the grid until
## another module gives it a better look (`set_visual`: the weapons module puts the part's
## own mesh on it), and its name close up.

const CELL_METRES := 0.09
const LABEL_RANGE := 5.0

var item := ""
var short_name := ""
var colour := Color(0.4, 0.4, 0.4)
var cells := Vector2i.ONE

var _box: MeshInstance3D
var _dressed := false


func _ready() -> void:
	add_to_group(&"loot")
	_box = MeshInstance3D.new()
	# A model may already be on it (it is dressed before entering the tree).
	_box.visible = not _dressed
	var mesh := BoxMesh.new()
	mesh.size = Vector3(cells.x * CELL_METRES, 0.05, cells.y * CELL_METRES)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour.darkened(0.2)
	mat.roughness = 0.8
	mesh.material = mat
	_box.mesh = mesh
	_box.position.y = 0.025
	add_child(_box)
	var label := Label3D.new()
	label.text = short_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.002
	label.outline_size = 10
	label.position.y = 0.22
	label.visibility_range_end = LABEL_RANGE
	add_child(label)


## Replaces the plain box with a model of the real thing, lying on the ground.
func set_visual(node: Node3D) -> void:
	_dressed = true
	if _box != null:
		_box.visible = false
	add_child(node)

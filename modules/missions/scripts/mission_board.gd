class_name MissionBoard
extends Node3D
## The mission board on the home tunnel's wall: a cork board on two posts with pinned
## sheets. Faces along its local -Z; looking at it and pressing F opens the board screen.

const BOARD := Vector3(1.8, 1.1, 0.08)
const BOARD_Y := 1.5
const POST := Vector3(0.1, 2.1, 0.1)
const WOOD := Color(0.4, 0.3, 0.2)
const CORK := Color(0.55, 0.42, 0.28)
const PAPER := Color(0.85, 0.82, 0.72)
## Pinned sheets: [centre x, centre y offset, w, h].
const SHEETS := [[-0.55, 0.12, 0.42, 0.55], [0.0, -0.05, 0.42, 0.6], [0.55, 0.15, 0.42, 0.5]]


func _ready() -> void:
	add_to_group(&"mission_board")
	_box(BOARD, Vector3(0.0, BOARD_Y, 0.0), CORK)
	for x: float in [-BOARD.x / 2.0, BOARD.x / 2.0]:
		_box(POST, Vector3(x, POST.y / 2.0, 0.02), WOOD)
	for s: Array in SHEETS:
		_box(Vector3(float(s[2]), float(s[3]), 0.01), Vector3(float(s[0]), BOARD_Y + float(s[1]), -BOARD.z / 2.0 - 0.006), PAPER)
	var label := Label3D.new()
	label.text = "MISSIONS"
	label.font_size = 64
	label.pixel_size = 0.004
	label.outline_size = 12
	label.position = Vector3(0.0, BOARD_Y + BOARD.y / 2.0 + 0.18, -0.06)
	label.rotation.y = PI
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

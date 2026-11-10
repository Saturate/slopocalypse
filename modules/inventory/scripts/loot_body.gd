class_name LootBody
extends Node3D
## What is left where a soldier or player died: a body lying on the ground that still holds
## everything they carried. Searching it (F) opens the loot screen; the server keeps the
## contents and removes the body after a while. Created by the server and, through the
## inventory module's spawner, on every client.

## Lying figure, local to the body: [size, centre] per part, the head towards -Z.
const PARTS := [
	[Vector3(0.42, 0.22, 0.62), Vector3(0.0, 0.11, 0.0)],
	[Vector3(0.24, 0.22, 0.26), Vector3(0.0, 0.12, -0.46)],
	[Vector3(0.16, 0.16, 0.82), Vector3(-0.12, 0.08, 0.72)],
	[Vector3(0.16, 0.16, 0.82), Vector3(0.14, 0.08, 0.7)],
	[Vector3(0.13, 0.13, 0.58), Vector3(-0.32, 0.07, -0.08)],
	[Vector3(0.13, 0.13, 0.58), Vector3(0.33, 0.07, 0.04)],
]
const HEAD := 1
const SKIN := Color(0.55, 0.43, 0.34)
const LABEL_RANGE := 6.0

var colour := Color(0.3, 0.33, 0.26)

var _label: Label3D


func _ready() -> void:
	add_to_group(&"loot_bodies")
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = colour
	cloth.roughness = 0.9
	var skin := StandardMaterial3D.new()
	skin.albedo_color = SKIN
	skin.roughness = 0.8
	for i in PARTS.size():
		var part: Array = PARTS[i]
		var mesh := BoxMesh.new()
		mesh.size = part[0]
		mesh.material = skin if i == HEAD else cloth
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.position = part[1]
		add_child(node)
	_label = Label3D.new()
	_label.text = "Body"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.pixel_size = 0.002
	_label.outline_size = 10
	_label.position.y = 0.55
	_label.visibility_range_end = LABEL_RANGE
	add_child(_label)


## Shown everywhere when the server says the body was emptied (or filled again).
func set_empty(empty: bool) -> void:
	set_meta(&"empty", empty)
	if _label != null:
		_label.text = "Empty body" if empty else "Body"

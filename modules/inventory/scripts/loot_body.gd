class_name LootBody
extends Node3D
## What is left where a soldier or player died: a body lying on the ground that still holds
## everything they carried. Searching it (F) opens the loot screen; the server keeps the
## contents and removes the body after a while. Created by the server and, through the
## inventory module's spawner, on every client. On clients the ragdoll that fell there (a
## Corpse) stands in for the simple figure drawn here, which only shows where there is none.
## No floating label: the interaction prompt names it when you look at it (#407).

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
## Above the body's spot, where the figure's chest is.
const AIM_HEIGHT := 0.15

var colour := Color(0.3, 0.33, 0.26)

var _figure: Array[MeshInstance3D] = []


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
		_figure.append(node)
	Corpse.link_near(self)


## Where to aim to search it: the ragdoll lying here on this machine if there is one (it fell
## up to a body length from the spot), else the spot itself.
func search_point() -> Vector3:
	var ragdoll: Variant = get_meta(Corpse.LINK) if has_meta(Corpse.LINK) else null
	if ragdoll is Node3D and is_instance_valid(ragdoll) and (ragdoll as Node3D).has_method(&"lying_at"):
		return (ragdoll as Node3D).call(&"lying_at")
	return global_position + Vector3.UP * AIM_HEIGHT


## Hidden while a ragdoll lies here instead.
func show_figure(on: bool) -> void:
	for part in _figure:
		part.visible = on


## Shown everywhere when the server says the body was emptied (or filled again).
func set_empty(empty: bool) -> void:
	set_meta(&"empty", empty)

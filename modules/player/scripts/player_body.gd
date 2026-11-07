class_name PlayerBody
extends RefCounted
## Helpers for the third-person body scene (player_body.tscn).

## Shoulder shift for your own view, in the shoulders' space: right, down and a little
## forward, so the rifle sits lower right and its sight no longer fills the screen.
const FIRST_PERSON_OFFSET := Vector3(0.07, -0.12, -0.08)


## First-person view of your own body: the torso, legs and head only cast a shadow (the
## camera sits inside the head), while the arms and whatever is held stay visible.
static func first_person(body: Node) -> void:
	var torso := body.get_node_or_null("Skeleton/Mesh") as GeometryInstance3D
	if torso != null:
		torso.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	# Right in front of the camera the arms catch the hidden torso's shadow as grainy acne
	# and full sun; first-person arms in most shooters skip shadows for the same reason.
	var arms := body.get_node_or_null("Skeleton/Arms") as MeshInstance3D
	if arms != null and arms.mesh != null:
		var mat := arms.mesh.surface_get_material(0).duplicate() as BaseMaterial3D
		if mat != null:
			mat.disable_receive_shadows = true
			arms.material_override = mat
		arms.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var aim := body.get_node_or_null("Skeleton/Aim")
	if aim != null:
		aim.set(&"view_offset", FIRST_PERSON_OFFSET)


## Where a held weapon mounts on the body.
static func weapon_socket(player: Node) -> Node3D:
	return player.get_node_or_null("Body/Skeleton/WeaponAttachment/WeaponSocket")

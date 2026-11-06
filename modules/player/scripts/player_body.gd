class_name PlayerBody
extends RefCounted
## Helpers for the third-person body scene (player_body.tscn).


## Hides every mesh under `body` from the camera but keeps its shadow.
static func shadows_only(body: Node) -> void:
	for child in body.get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		shadows_only(child)


## Where a held weapon mounts on the body.
static func weapon_socket(player: Node) -> Node3D:
	return player.get_node_or_null("Body/Hips/Spine/Chest/WeaponSocket")

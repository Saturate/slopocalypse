extends SkeletonModifier3D
## Runs after the animation each frame: tilts spine, chest, shoulders and head toward the aim
## pitch so the held rifle (on the shoulders bone) points where the player looks, whatever
## the clip.
## No class_name and no autoloads, so the body builder can attach it.

## Radians, positive looks up, the same sign as the camera Head node's X rotation.
var pitch := 0.0

## How the pitch is shared out. Spine, chest and shoulders add up to the full pitch, so the
## rifle on the shoulders points at the aim while the back only bends a little; the head
## (a child of the chest) takes the rest of its own share on top of the back's.
const SHARES := {&"Spine": 0.1, &"Chest": 0.15, &"Shoulders": 0.75, &"Head": 0.5}

## First person only: moves the shoulders (arms and rifle together) down and to the right
## so the one rifle sits in the lower right of the view instead of against the eye. Other
## players see the unshifted pose. Set by PlayerBody.first_person().
var view_offset := Vector3.ZERO

var _bones: Dictionary[StringName, int] = {}


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if _bones.is_empty():
		for bone: StringName in SHARES:
			_bones[bone] = skeleton.find_bone(bone)
	for bone: StringName in SHARES:
		var i: int = _bones[bone]
		if i < 0:
			continue
		var tilt := Quaternion(Vector3.RIGHT, pitch * float(SHARES[bone]))
		skeleton.set_bone_pose_rotation(i, skeleton.get_bone_pose_rotation(i) * tilt)
		if bone == &"Shoulders" and view_offset != Vector3.ZERO:
			skeleton.set_bone_pose_position(i, skeleton.get_bone_pose_position(i) + view_offset)

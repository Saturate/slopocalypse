extends SkeletonModifier3D
## Runs after the animation each frame: tilts spine, chest, shoulders and head toward the aim
## pitch so the held rifle (on the shoulders bone) points where the player looks, whatever
## the clip. While aiming down sights it also brings the sight to the eye. No class_name
## and no autoloads, so the body builder can attach it.

## Radians, positive looks up, the same sign as the camera Head node's X rotation.
var pitch := 0.0
## Radians of sideways lean, positive to the right. Shared by spine and chest.
var lean := 0.0
const LEAN_SHARES := {&"Spine": 0.45, &"Chest": 0.55}

## How the pitch is shared out. Spine, chest and shoulders add up to the full pitch, so the
## rifle on the shoulders points at the aim while the back only bends a little; the head
## (a child of the chest) takes the rest of its own share on top of the back's.
const SHARES := {&"Spine": 0.1, &"Chest": 0.15, &"Shoulders": 0.75, &"Head": 0.5}

## First person only: where the sight sits in the camera's space at the hip (right, down,
## forward). The arms and rifle are then held by the view like a view model: they turn with
## the camera, so looking down never shows the shoulders from above. Other players see the
## animated pose. Zero means third person. Set by PlayerBody.first_person().
var hip_sight := Vector3.ZERO

## Aiming down sights, 0 (hip) to 1 (sight on the eye). Set by the body animator.
var ads := 0.0
## The sight's eye point in the Shoulders bone's space, and the camera it should sit in
## front of. Set by the body animator from the held weapon's `Sight` marker.
var sight := Vector3.ZERO
var eye: Node3D
## How far in front of the eye the sight's rear sits when fully aimed.
var eye_relief := 0.09
## While aiming, the head leans left onto the stock so the rifle runs along the right
## cheek instead of through the face. Only the body moves; the camera stays where it is.
const CHEEK_WELD := Vector3(-0.05, -0.015, 0.0)
const CHEEK_TILT := 0.18

var _bones: Dictionary[StringName, int] = {}


func _process_modification_with_delta(_delta: float) -> void:
	var prof := Prof.start()
	_modify_tick(_delta)
	Prof.stop(&"player/body_aim_modifier:frame", prof)


func _modify_tick(_delta: float) -> void:
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
		# Lean rolls about the body's forward axis (skeleton -Z), taken into this bone's own
		# space: the bones' local axes don't line up with the body, and rolling about a local
		# axis twisted the torso instead of tilting it.
		var forward := (skeleton.get_bone_global_pose(i).basis.inverse() * Vector3.FORWARD).normalized()
		var roll := Quaternion(forward, lean * float(LEAN_SHARES.get(bone, 0.0)))
		skeleton.set_bone_pose_rotation(i, skeleton.get_bone_pose_rotation(i) * roll * tilt)
	var shoulders: int = _bones.get(&"Shoulders", -1)
	if shoulders < 0:
		return
	var offset := Vector3.ZERO
	var on_eye := Vector3(0.0, 0.0, -eye_relief)
	if hip_sight != Vector3.ZERO and is_instance_valid(eye):
		offset = _sight_to(skeleton, shoulders, hip_sight.lerp(on_eye, ads), 1.0)
	elif ads > 0.0 and is_instance_valid(eye):
		offset = _sight_to(skeleton, shoulders, on_eye, ads) * ads
	if offset != Vector3.ZERO:
		skeleton.set_bone_pose_position(shoulders, skeleton.get_bone_pose_position(shoulders) + offset)
	var head: int = _bones.get(&"Head", -1)
	if ads > 0.0 and head >= 0:
		skeleton.set_bone_pose_position(head, skeleton.get_bone_pose_position(head) + CHEEK_WELD * ads)
		var tilt := Quaternion(Vector3.BACK, CHEEK_TILT * ads)
		skeleton.set_bone_pose_rotation(head, skeleton.get_bone_pose_rotation(head) * tilt)


## Turns the shoulders so the rifle points exactly along the view (blended by `weight`), and
## returns how far, in the shoulders' parent space, they must move to put the sight at
## `target`, a point in the eye's space. The animation's sway fades out by `weight`.
func _sight_to(skeleton: Skeleton3D, shoulders: int, target_in_eye: Vector3, weight: float) -> Vector3:
	var parent_global := skeleton.get_bone_global_pose(skeleton.get_bone_parent(shoulders))
	var eye_xf := skeleton.global_transform.affine_inverse() * eye.global_transform
	var aligned := (parent_global.basis.inverse() * eye_xf.basis.orthonormalized()).get_rotation_quaternion()
	var rot := skeleton.get_bone_pose_rotation(shoulders).slerp(aligned, weight)
	skeleton.set_bone_pose_rotation(shoulders, rot)
	var shoulders_global := parent_global * Transform3D(Basis(rot), skeleton.get_bone_pose_position(shoulders))
	var target := eye_xf * target_in_eye
	var current := shoulders_global * sight
	return parent_global.basis.inverse() * (target - current)

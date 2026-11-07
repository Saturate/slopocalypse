extends SkeletonModifier3D
## Runs after the aim modifier: bends each arm (upper arm, forearm) so its hand reaches the
## grip point the held gun names, so a pistol, a short handguard and a long one are each
## held where they should be. The elbow keeps bending the way the pose already had it.
## No class_name and no autoloads, so the body builder can attach it.

const ARMS := {
	&"R": [&"UpperArm_R", &"LowerArm_R", &"Hand_R"],
	&"L": [&"UpperArm_L", &"LowerArm_L", &"Hand_L"],
}

## Wrist targets in the Shoulders bone's space, per side (&"R", &"L"); a side without one
## keeps its animated pose. Set every frame by the body animator from the gun's markers.
var targets: Dictionary = {}

var _bones: Dictionary = {}
var _shoulders := -1


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or targets.is_empty():
		return
	if _bones.is_empty():
		_shoulders = skeleton.find_bone(&"Shoulders")
		for side: StringName in ARMS:
			var ids: Array[int] = []
			for bone: StringName in ARMS[side]:
				ids.append(skeleton.find_bone(bone))
			_bones[side] = ids
	if _shoulders < 0:
		return
	var shoulders := skeleton.get_bone_global_pose(_shoulders)
	for side: StringName in targets:
		var ids: Array[int] = _bones.get(side, [])
		if ids.size() == 3 and not ids.has(-1):
			_solve(skeleton, ids, shoulders * (targets[side] as Vector3))


## Two-bone IK in skeleton space. Limbs run along their bones' +Y.
func _solve(skeleton: Skeleton3D, ids: Array[int], target: Vector3) -> void:
	var upper := skeleton.get_bone_global_pose(ids[0])
	var lower := skeleton.get_bone_global_pose(ids[1])
	var hand := skeleton.get_bone_global_pose(ids[2])
	var s := upper.origin
	var a := s.distance_to(lower.origin)
	var b := lower.origin.distance_to(hand.origin)
	var to_target := target - s
	var d := clampf(to_target.length(), absf(a - b) + 0.001, a + b - 0.001)
	if to_target.length_squared() < 1e-8:
		return
	var dir := to_target.normalized()
	# Bend toward where the elbow already is, so arms keep the pose's character.
	var pole := lower.origin - s
	var side := (pole - dir * pole.dot(dir))
	if side.length_squared() < 1e-8:
		side = Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
	side = side.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var elbow := s + dir * a * cos_a + side * a * sqrt(1.0 - cos_a * cos_a)
	var reach := s + dir * d
	_aim_bone(skeleton, ids[0], upper, elbow)
	var new_lower := skeleton.get_bone_global_pose(ids[1])
	_aim_bone(skeleton, ids[1], new_lower, reach)


## Turns bone `i` (whose global pose is `global`) so its +Y points at `at`.
func _aim_bone(skeleton: Skeleton3D, i: int, global: Transform3D, at: Vector3) -> void:
	var from_dir := global.basis.y.normalized()
	var to_dir := (at - global.origin).normalized()
	if from_dir.is_equal_approx(to_dir) or to_dir.is_zero_approx():
		return
	var turned := Basis(Quaternion(from_dir, to_dir)) * global.basis
	var parent := skeleton.get_bone_parent(i)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(i, (parent_basis.inverse() * turned).orthonormalized().get_rotation_quaternion())

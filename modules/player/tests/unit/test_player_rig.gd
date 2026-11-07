extends GdUnitTestSuite
## The third-person body is a skinned mesh on a Skeleton3D, animated by clips that an
## AnimationTree blends. These checks catch a broken rig without looking at it.

const BODY := "res://modules/player/scenes/player_body.tscn"
const BONES := ["Hips", "Spine", "Chest", "Shoulders", "Head", "UpperArm_R", "LowerArm_R", "Hand_R", "UpperArm_L", "LowerArm_L", "Hand_L", "UpperLeg_L", "LowerLeg_L", "UpperLeg_R", "LowerLeg_R"]
const CLIPS := ["idle", "walk", "run", "crouch_idle", "crouch_walk", "slide", "fall"]
## Boot sole below the knee joint, in the shin bone's space.
const SOLE := Vector3(0.0, -0.405, 0.0)

var _body: Node3D
var _skeleton: Skeleton3D
var _anims: AnimationPlayer


func before_test() -> void:
	_body = auto_free((load(BODY) as PackedScene).instantiate())
	add_child(_body)
	_skeleton = _body.get_node("Skeleton")
	_anims = _body.get_node("AnimationPlayer")
	# The tree would overwrite the poses the tests set through the player.
	(_body.get_node("AnimationTree") as AnimationTree).active = false


func test_has_a_humanoid_skeleton() -> void:
	for bone: String in BONES:
		assert_int(_skeleton.find_bone(bone)).override_failure_message("missing bone " + bone).is_not_equal(-1)


func test_mesh_is_skinned_to_the_skeleton() -> void:
	var mesh_inst: MeshInstance3D = _skeleton.get_node("Mesh")
	assert_object(mesh_inst.skin).is_not_null()
	assert_object(mesh_inst.get_node_or_null(mesh_inst.skeleton)).is_same(_skeleton)
	var format: int = (mesh_inst.mesh as ArrayMesh).surface_get_format(0)
	assert_bool(format & Mesh.ARRAY_FORMAT_BONES != 0).is_true()
	assert_bool(format & Mesh.ARRAY_FORMAT_WEIGHTS != 0).is_true()


func test_every_clip_animates_real_bones() -> void:
	for clip: String in CLIPS:
		assert_bool(_anims.has_animation(clip)).override_failure_message("missing clip " + clip).is_true()
		var anim := _anims.get_animation(clip)
		assert_int(anim.get_track_count()).is_greater(0)
		for t in anim.get_track_count():
			var path := anim.track_get_path(t)
			assert_str(String(path.get_concatenated_names())).is_equal("Skeleton")
			var bone := String(path.get_concatenated_subnames())
			assert_int(_skeleton.find_bone(bone)).override_failure_message("%s animates missing bone %s" % [clip, bone]).is_not_equal(-1)


func test_feet_stay_on_the_ground() -> void:
	for clip: String in ["idle", "walk", "run", "crouch_idle", "crouch_walk"]:
		_anims.play(clip)
		_anims.seek(0.0, true)
		var lowest := INF
		for side in ["L", "R"]:
			var shin := _skeleton.find_bone("LowerLeg_" + side)
			lowest = minf(lowest, (_skeleton.get_bone_global_pose(shin) * SOLE).y)
		assert_float(lowest).override_failure_message("%s: lowest sole at %.3f m" % [clip, lowest]).is_between(-0.06, 0.08)


func test_weapon_socket_rides_the_shoulders_with_the_arms() -> void:
	var attachment: BoneAttachment3D = _skeleton.get_node("WeaponAttachment")
	assert_str(attachment.bone_name).is_equal("Shoulders")
	for arm: String in ["UpperArm_R", "UpperArm_L"]:
		assert_int(_skeleton.get_bone_parent(_skeleton.find_bone(arm))).is_equal(_skeleton.find_bone("Shoulders"))
	assert_object(attachment.get_node_or_null("WeaponSocket")).is_not_null()

extends GdUnitTestSuite
## Which limb a killing blow takes: a strong enough shot cuts at the joint above where it hit,
## the head only when the data allows it, and a blast takes the limbs nearest it, more the
## closer it went off, none beyond its reach.

var _cfg: Dictionary


func before_test() -> void:
	_cfg = LimbSevering.config().duplicate()
	_cfg["shot_sever_damage"] = 25.0
	_cfg["headshot_sever"] = false
	_cfg["blast_sever_radius"] = 3.0
	_cfg["blast_max_limbs"] = 2.0
	_cfg["blast_all_limbs_within"] = 1.5


func test_a_shot_cuts_at_the_joint_above_where_it_hit() -> void:
	assert_str(LimbRules.shot_limb("Hand_L", 30.0, _cfg)).is_equal("forearm_L")
	assert_str(LimbRules.shot_limb("LowerArm_R", 30.0, _cfg)).is_equal("forearm_R")
	assert_str(LimbRules.shot_limb("UpperArm_R", 30.0, _cfg)).is_equal("upper_arm_R")
	assert_str(LimbRules.shot_limb("UpperLeg_L", 30.0, _cfg)).is_equal("thigh_L")
	assert_str(LimbRules.shot_limb("LowerLeg_L", 30.0, _cfg)).is_equal("shin_L")
	assert_array(LimbRules.bones("upper_arm_L")).is_equal(["UpperArm_L", "LowerArm_L", "Hand_L"])


func test_weak_shots_torso_shots_and_heads_cut_nothing() -> void:
	assert_str(LimbRules.shot_limb("Hand_L", 20.0, _cfg)).is_empty()
	assert_str(LimbRules.shot_limb("Chest", 100.0, _cfg)).is_empty()
	assert_str(LimbRules.shot_limb("Head", 100.0, _cfg)).is_empty()
	_cfg["headshot_sever"] = true
	assert_str(LimbRules.shot_limb("Head", 100.0, _cfg)).is_equal("head")


func test_a_blast_takes_the_nearest_limbs_more_when_closer() -> void:
	var distances := {"upper_arm_L": 1.0, "upper_arm_R": 1.4, "thigh_L": 0.6, "thigh_R": 2.0, "head": 1.8, "forearm_L": 0.1}
	assert_array(LimbRules.blast_limbs(1.0, distances, _cfg)).is_equal(["thigh_L", "upper_arm_L"])
	assert_array(LimbRules.blast_limbs(2.5, distances, _cfg)).is_equal(["thigh_L"])
	assert_array(LimbRules.blast_limbs(3.5, distances, _cfg)).is_empty()

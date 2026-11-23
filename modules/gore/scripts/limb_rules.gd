class_name LimbRules
extends RefCounted
## Which limb a killing blow takes off (#387), as plain rules over bone names and distances so
## they can be tested without a body. A limb is named by the bone it is cut at and takes every
## bone below it: an upper arm takes the forearm and hand, a forearm the hand, a thigh the shin.

## Limb name -> [the bone it is cut at, the bones it takes with it].
const LIMBS := {
	"upper_arm_L": ["UpperArm_L", ["UpperArm_L", "LowerArm_L", "Hand_L"]],
	"upper_arm_R": ["UpperArm_R", ["UpperArm_R", "LowerArm_R", "Hand_R"]],
	"forearm_L": ["LowerArm_L", ["LowerArm_L", "Hand_L"]],
	"forearm_R": ["LowerArm_R", ["LowerArm_R", "Hand_R"]],
	"thigh_L": ["UpperLeg_L", ["UpperLeg_L", "LowerLeg_L"]],
	"thigh_R": ["UpperLeg_R", ["UpperLeg_R", "LowerLeg_R"]],
	"shin_L": ["LowerLeg_L", ["LowerLeg_L"]],
	"shin_R": ["LowerLeg_R", ["LowerLeg_R"]],
	"head": ["Head", ["Head"]],
}
## What a shot on a bone cuts: at the joint above where it hit.
const SHOT_LIMB := {
	"UpperArm_L": "upper_arm_L", "UpperArm_R": "upper_arm_R",
	"LowerArm_L": "forearm_L", "LowerArm_R": "forearm_R", "Hand_L": "forearm_L", "Hand_R": "forearm_R",
	"UpperLeg_L": "thigh_L", "UpperLeg_R": "thigh_R", "LowerLeg_L": "shin_L", "LowerLeg_R": "shin_R",
	"Head": "head",
}
## What a blast can take: whole limbs and the head.
const BLAST_LIMBS: Array[String] = ["upper_arm_L", "upper_arm_R", "thigh_L", "thigh_R", "head"]


static func root_bone(limb: String) -> String:
	return String((LIMBS[limb] as Array)[0])


static func bones(limb: String) -> Array:
	return (LIMBS[limb] as Array)[1]


## The limb a killing shot on `bone_name` with `damage` takes off, or "" for none: too weak,
## not a limb, or the head without `headshot_sever`.
static func shot_limb(bone_name: String, damage: float, cfg: Dictionary) -> String:
	var limb := String(SHOT_LIMB.get(bone_name, ""))
	if limb.is_empty() or damage < float(cfg["shot_sever_damage"]):
		return ""
	if limb == "head" and not bool(cfg["headshot_sever"]):
		return ""
	return limb


## The limbs a blast `body_distance` metres from the body takes off, nearest first, from
## `limb_distances` (limb -> metres from the blast): none beyond `blast_sever_radius`, up to
## `blast_max_limbs` within `blast_all_limbs_within`, one in between.
static func blast_limbs(body_distance: float, limb_distances: Dictionary, cfg: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if body_distance > float(cfg["blast_sever_radius"]):
		return out
	var count := int(cfg["blast_max_limbs"]) if body_distance <= float(cfg["blast_all_limbs_within"]) else mini(1, int(cfg["blast_max_limbs"]))
	var limbs: Array[String] = []
	for limb: String in BLAST_LIMBS:
		if limb_distances.has(limb):
			limbs.append(limb)
	limbs.sort_custom(func(a: String, b: String) -> bool: return float(limb_distances[a]) < float(limb_distances[b]))
	for limb in limbs:
		if out.size() >= count:
			break
		out.append(limb)
	return out

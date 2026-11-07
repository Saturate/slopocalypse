extends SceneTree
## Builds modules/player/scenes/player_body.tscn: a chunky low-poly soldier as one skinned
## mesh on a Skeleton3D, with an AnimationPlayer of clips (idle, walk, run, crouch, slide,
## fall) and an AnimationTree that blends them. Bones use humanoid names (Hips, Spine,
## Chest, Shoulders, Head, UpperArm_R ...) so a rigged model from the art teammate can replace this.
## Feet at the origin, facing -Z, 1.8 m tall.
##
## Every part is weighted fully to one bone: rigid segments suit the blocky style and keep
## joints from smearing. Clips are generated from pose functions sampled over the cycle;
## grounded clips solve the hip height per key so the lower boot sole touches the ground.

const OUT := "res://modules/player/scenes/player_body.tscn"
const PLAYER_DATA := "res://modules/player/data/player.json"
const AIM_SCRIPT := "res://modules/player/scripts/body_aim_modifier.gd"

const CAMO := Color(0.33, 0.37, 0.26)
const CAMO_DARK := Color(0.26, 0.29, 0.2)
const VEST := Color(0.45, 0.42, 0.3)
const POUCH := Color(0.38, 0.35, 0.24)
const SKIN := Color(0.78, 0.6, 0.47)
const HELMET := Color(0.3, 0.33, 0.24)
const DARK := Color(0.12, 0.12, 0.12)
const BOOT := Color(0.2, 0.16, 0.12)
const GLOVE := Color(0.16, 0.15, 0.14)

const HIPS_HEIGHT := 0.86
## Leg chain: hip joint below the Hips bone, thigh length, knee to boot sole.
const HIP_JOINT := 0.07
const THIGH := 0.38
const SHIN := 0.405
## Travel per full walk cycle (two steps), so the feet do not skate at the matching speed.
const WALK_STRIDE := 2.6
const RUN_STRIDE := 3.6
const CROUCH_STRIDE := 1.6
const KEYS_PER_CYCLE := 16

## Rifle hold, in chest space. The rifle sits right of centre with its stock in the right
## shoulder; the hands go where the rifle mesh has its pistol grip and handguard, and the
## elbows are solved from the arm lengths, pointing down and out.
const RIFLE_AT := Vector3(0.08, 0.25, -0.36)
const GRIP := RIFLE_AT + Vector3(0.0, -0.08, 0.11)
const FORE := RIFLE_AT + Vector3(0.0, -0.02, -0.18)
const R_SHOULDER := Vector3(0.28, 0.27, 0)
const L_SHOULDER := Vector3(-0.28, 0.27, 0)
const UPPER_ARM := 0.33
const FOREARM := 0.33
const R_ELBOW_POLE := Vector3(1.0, -1.0, 0.3)
const L_ELBOW_POLE := Vector3(-0.6, -1.0, 0.0)

var _skel: Skeleton3D


func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLAYER_DATA))
	var root := Node3D.new()
	root.name = "PlayerBody"
	_skel = Skeleton3D.new()
	_skel.name = "Skeleton"
	root.add_child(_skel)
	_build_bones()
	_build_mesh()

	var attachment := BoneAttachment3D.new()
	attachment.name = "WeaponAttachment"
	attachment.bone_name = "Shoulders"
	_skel.add_child(attachment)
	# Where the weapons module mounts the third-person rifle: grip in the right hand.
	var socket := Marker3D.new()
	socket.name = "WeaponSocket"
	# The attachment follows the Shoulders bone, so convert from chest space.
	socket.position = RIFLE_AT - Vector3(0, R_SHOULDER.y, 0)
	attachment.add_child(socket)

	# After the animation: tilts spine, chest and head toward the aim.
	var aim := SkeletonModifier3D.new()
	aim.name = "Aim"
	aim.set_script(load(AIM_SCRIPT))
	_skel.add_child(aim)

	var anims := AnimationPlayer.new()
	anims.name = "AnimationPlayer"
	anims.add_animation_library(&"", _build_clips(data))
	root.add_child(anims)
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	tree.anim_player = NodePath("../AnimationPlayer")
	tree.tree_root = _build_tree(data)
	root.add_child(tree)

	var result := SceneBuilder.pack_and_save(root, OUT)
	root.free()
	if result.error != OK:
		push_error(result.message)
		quit(1)
		return
	quit(0)


func _build_bones() -> void:
	_bone("Hips", "", _at(Vector3(0, HIPS_HEIGHT, 0)))
	_bone("Spine", "Hips", _at(Vector3(0, 0.09, 0)))
	_bone("Chest", "Spine", _at(Vector3(0, 0.18, 0)))
	_bone("Head", "Chest", _at(Vector3(0, 0.38, 0)))
	# The arms and rifle hang from the shoulder line, so aiming pitches them as one piece
	# around the shoulders instead of bending the whole back.
	_bone("Shoulders", "Chest", _at(Vector3(0, R_SHOULDER.y, 0)))
	# Arm bones point along their limbs (+Y down the bone, as in Blender), resting in the
	# rifle hold so the clips leave the arms alone and the aim moves them with the chest.
	var chest := _skel.get_bone_global_rest(_skel.find_bone("Chest"))
	for arm in [["R", R_SHOULDER, GRIP, R_ELBOW_POLE], ["L", L_SHOULDER, FORE, L_ELBOW_POLE]]:
		var side: String = arm[0]
		var shoulder: Vector3 = chest * (arm[1] as Vector3)
		var hand: Vector3 = chest * (arm[2] as Vector3)
		var elbow := _elbow(shoulder, hand, arm[3])
		_bone_global("UpperArm_" + side, "Shoulders", Transform3D(_along(elbow - shoulder), shoulder))
		_bone_global("LowerArm_" + side, "UpperArm_" + side, Transform3D(_along(hand - elbow), elbow))
		_bone_global("Hand_" + side, "LowerArm_" + side, Transform3D(_along(hand - elbow), hand))
	for side in [["L", -1.0], ["R", 1.0]]:
		_bone("UpperLeg_" + side[0], "Hips", _at(Vector3(side[1] * 0.11, -HIP_JOINT, 0)))
		_bone("LowerLeg_" + side[0], "UpperLeg_" + side[0], _at(Vector3(0, -THIGH, 0)))


func _build_mesh() -> void:
	var st := LowPoly.begin()
	# Chunky proportions: sturdy legs, a big torso and an oversized helmet read well at
	# distance in a low-poly shooter.
	_weight(st, "Hips")
	_box(st, "Hips", Vector3(0.4, 0.2, 0.25), 0.04, Vector3(0, -0.02, 0), CAMO_DARK)
	_box(st, "Hips", Vector3(0.42, 0.06, 0.27), 0.015, Vector3(0, 0.07, 0), DARK)
	_box(st, "Hips", Vector3(0.1, 0.12, 0.08), 0.02, Vector3(0.2, 0.0, 0.02), POUCH)

	_weight(st, "Chest")
	_box(st, "Chest", Vector3(0.46, 0.48, 0.27), 0.06, Vector3(0, 0.1, 0), CAMO)
	# Plate carrier and pouches give the silhouette its soldier read.
	_box(st, "Chest", Vector3(0.52, 0.38, 0.34), 0.05, Vector3(0, 0.1, 0), VEST)
	for x in [-0.15, 0.0, 0.15]:
		_box(st, "Chest", Vector3(0.12, 0.14, 0.07), 0.02, Vector3(x, -0.01, -0.2), POUCH)
	_box(st, "Chest", Vector3(0.36, 0.14, 0.1), 0.03, Vector3(0, 0.2, 0.19), POUCH)
	_box(st, "Chest", Vector3(0.14, 0.08, 0.12), 0.02, Vector3(0, 0.33, 0), CAMO_DARK)

	_weight(st, "Head")
	_box(st, "Head", Vector3(0.22, 0.22, 0.23), 0.06, Vector3(0, 0.1, 0), SKIN)
	# Helmet: shell, brim and side shells so it reads as a helmet, not a cap.
	_box(st, "Head", Vector3(0.3, 0.16, 0.32), 0.07, Vector3(0, 0.22, 0.01), HELMET)
	_box(st, "Head", Vector3(0.33, 0.035, 0.36), 0.012, Vector3(0, 0.16, 0.0), HELMET.darkened(0.15))
	for x in [-0.155, 0.155]:
		_box(st, "Head", Vector3(0.04, 0.13, 0.22), 0.015, Vector3(x, 0.14, 0.02), HELMET.darkened(0.1))
	_box(st, "Head", Vector3(0.2, 0.05, 0.03), 0.012, Vector3(0, 0.12, -0.12), DARK)
	_box(st, "Head", Vector3(0.09, 0.03, 0.03), 0.01, Vector3(0, 0.03, -0.115), SKIN.darkened(0.2))

	for side in ["R", "L"]:
		_weight(st, "UpperArm_" + side)
		_limb(st, "UpperArm_" + side, 0.13, CAMO)
		# Shoulder pads round off the joint.
		_box(st, "UpperArm_" + side, Vector3(0.16, 0.17, 0.15), 0.05, Vector3(0, 0.0, 0), CAMO_DARK)
		_weight(st, "LowerArm_" + side)
		_limb(st, "LowerArm_" + side, 0.115, CAMO_DARK)
		_weight(st, "Hand_" + side)
		_box(st, "Hand_" + side, Vector3(0.1, 0.11, 0.11), 0.03, Vector3.ZERO, GLOVE)

	for side in [["L", -1.0], ["R", 1.0]]:
		var upper: String = "UpperLeg_" + side[0]
		var lower: String = "LowerLeg_" + side[0]
		_weight(st, upper)
		_box(st, upper, Vector3(0.19, 0.4, 0.21), 0.05, Vector3(0, -0.18, 0), CAMO)
		_box(st, upper, Vector3(0.08, 0.13, 0.1), 0.02, Vector3(side[1] * 0.1, -0.18, 0), POUCH)
		_weight(st, lower)
		_box(st, lower, Vector3(0.17, 0.33, 0.19), 0.05, Vector3(0, -0.15, 0), CAMO_DARK)
		_box(st, lower, Vector3(0.18, 0.11, 0.07), 0.025, Vector3(0, 0.0, -0.1), DARK)
		_box(st, lower, Vector3(0.19, 0.13, 0.31), 0.045, Vector3(0, -0.34, -0.05), BOOT)

	var inst := MeshInstance3D.new()
	inst.name = "Mesh"
	inst.mesh = LowPoly.finish(st, LowPoly.material(0.85))
	inst.skin = _skel.create_skin_from_rest_transforms()
	inst.skeleton = NodePath("..")
	_skel.add_child(inst)


# --- Clips -------------------------------------------------------------------------------

func _build_clips(data: Dictionary) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	lib.add_animation(&"idle", _clip(2.4, _idle, true))
	lib.add_animation(&"walk", _clip(WALK_STRIDE / float(data["walk_speed"]), _stride.bind(30.0, 8.0, 42.0, -6.0, 5.0), true))
	lib.add_animation(&"run", _clip(RUN_STRIDE / float(data["sprint_speed"]), _stride.bind(48.0, 15.0, 95.0, -36.0, 8.0, -35.0), true))
	lib.add_animation(&"crouch_idle", _clip(2.4, _crouch_idle, true))
	lib.add_animation(&"crouch_walk", _clip(CROUCH_STRIDE / float(data["crouch_speed"]), _crouch_walk, true))
	lib.add_animation(&"slide", _clip(1.0, _slide, true))
	lib.add_animation(&"fall", _clip(1.0, _fall, false))
	return lib


## Pose at cycle phase `p` (0..1): bone -> Euler degrees on top of the rest pose. Positive
## X swings a leg forward (-Z) and tips the spine back; knees bend with negative X.
func _idle(p: float) -> Dictionary:
	var breathe := sin(TAU * p)
	return {"Spine": Vector3(-2, 0, 0), "Chest": Vector3(1.5 * breathe, 0, 0), "Head": Vector3(-0.8 * breathe, 0, 0),
		"UpperLeg_L": Vector3(4, 0, -3), "LowerLeg_L": Vector3(-6, 0, 0), "UpperLeg_R": Vector3(-3, 0, 3), "LowerLeg_R": Vector3(-4, 0, 0)}


## `carry` tips the rifle down from level: 0 while walking, a low-ready carry when sprinting.
func _stride(p: float, swing: float, knee_stance: float, knee_swing: float, lean: float, twist: float, carry: float = 0.0) -> Dictionary:
	var pose := {"Spine": Vector3(lean, 0, 0), "carry": carry}
	for side in [["L", 0.0], ["R", 0.5]]:
		var q := TAU * (p + float(side[1]))
		# Front at q = 0, back at q = PI: stance first (knee nearly straight), then the swing
		# forward with the knee folded to clear the ground.
		pose["UpperLeg_" + side[0]] = Vector3(swing * cos(q), 0, 0)
		pose["LowerLeg_" + side[0]] = Vector3(-(knee_stance + knee_swing * maxf(0.0, -sin(q))), 0, 0)
	# Hips turn with the forward leg, the chest turns back against them.
	var hips_twist := twist * cos(TAU * p)
	pose["Hips"] = Vector3(0, -hips_twist, 0)
	# Sprinting folds the chest forward too, so the lean reads from the side.
	pose["Chest"] = Vector3(minf(lean + 6.0, 0.0) * 0.4, hips_twist * 1.4, 0)
	pose["Head"] = Vector3(-lean * 0.6, -hips_twist * 0.4, 0)
	return pose


func _crouch_idle(p: float) -> Dictionary:
	var breathe := sin(TAU * p)
	return {"Spine": Vector3(-28, 0, 0), "Chest": Vector3(-10 + breathe, 0, 0), "Head": Vector3(32, 0, 0),
		"UpperLeg_L": Vector3(80, 0, -6), "LowerLeg_L": Vector3(-130, 0, 0), "UpperLeg_R": Vector3(62, 0, 6), "LowerLeg_R": Vector3(-118, 0, 0)}


func _crouch_walk(p: float) -> Dictionary:
	var pose := {"Spine": Vector3(-28, 0, 0), "Chest": Vector3(-10, 0, 0), "Head": Vector3(32, 0, 0)}
	for side in [["L", 0.0], ["R", 0.5]]:
		var q := TAU * (p + float(side[1]))
		pose["UpperLeg_" + side[0]] = Vector3(60 + 32 * cos(q), 0, 0)
		pose["LowerLeg_" + side[0]] = Vector3(-(100 + 35 * maxf(0.0, -sin(q))), 0, 0)
	return pose


func _slide(_p: float) -> Dictionary:
	# Leading leg out straight, the other folded under, leaning back into the slide.
	return {"Spine": Vector3(28, 0, 0), "Chest": Vector3(8, 0, 0), "Head": Vector3(-30, 0, 0),
		"UpperLeg_L": Vector3(70, 0, 0), "LowerLeg_L": Vector3(-5, 0, 0), "UpperLeg_R": Vector3(30, 0, 10), "LowerLeg_R": Vector3(-125, 0, 0)}


func _fall(_p: float) -> Dictionary:
	# Knees pulled up, feet off the ground: in the air, not mid-stride.
	return {"Spine": Vector3(-10, 0, 0), "Head": Vector3(10, 0, 0), "airborne": true,
		"UpperLeg_L": Vector3(85, 0, -8), "LowerLeg_L": Vector3(-115, 0, 0), "UpperLeg_R": Vector3(60, 0, 8), "LowerLeg_R": Vector3(-105, 0, 0)}


## Samples `pose` over one cycle into rotation keys, plus a Hips position track. Every clip
## keys the same bones so blends never fall back to rest halfway.
func _clip(length: float, pose: Callable, loop: bool) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var bones := ["Hips", "Spine", "Chest", "Shoulders", "Head", "UpperLeg_L", "LowerLeg_L", "UpperLeg_R", "LowerLeg_R"]
	var rot_tracks := {}
	for bone: String in bones:
		var t := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(t, NodePath("Skeleton:" + bone))
		rot_tracks[bone] = t
	var pos_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos_track, NodePath("Skeleton:Hips"))
	var keys := KEYS_PER_CYCLE if loop else 1
	for k in keys + 1:
		var p := float(k) / float(keys)
		var time := p * length
		var at: Dictionary = pose.call(fmod(p, 1.0))
		# Shoulders undo the torso's pitch so the rifle stays level (on the aim) whatever
		# the legs and back do, then tip by the clip's carry angle.
		var torso := (at.get("Spine", Vector3.ZERO) as Vector3).x + (at.get("Chest", Vector3.ZERO) as Vector3).x
		at["Shoulders"] = Vector3(-torso + float(at.get("carry", 0.0)), 0, 0)
		for bone: String in bones:
			var euler: Vector3 = at.get(bone, Vector3.ZERO)
			var rest := _skel.get_bone_rest(_skel.find_bone(bone))
			var rot := rest.basis.get_rotation_quaternion() * Quaternion.from_euler(euler * (PI / 180.0))
			anim.rotation_track_insert_key(rot_tracks[bone], time, rot)
		var hips_y := HIPS_HEIGHT if at.get("airborne", false) else _grounded_hips(at)
		anim.position_track_insert_key(pos_track, time, Vector3(0, hips_y, 0))
	return anim


## Hips height that puts the lower boot sole on the ground for this pose.
func _grounded_hips(pose: Dictionary) -> float:
	var drop := 0.0
	for side in ["L", "R"]:
		var thigh := deg_to_rad((pose.get("UpperLeg_" + side, Vector3.ZERO) as Vector3).x)
		var knee := deg_to_rad((pose.get("LowerLeg_" + side, Vector3.ZERO) as Vector3).x)
		drop = maxf(drop, HIP_JOINT + THIGH * cos(thigh) + SHIN * cos(thigh + knee))
	return drop


# --- Blend tree --------------------------------------------------------------------------

## loco (idle/walk/run by speed) -> crouch blend -> air blend -> slide blend -> output.
## The animator drives the blend parameters from the player's synced state.
func _build_tree(data: Dictionary) -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = float(data["sprint_speed"])
	loco.add_blend_point(_play(&"idle"), 0.0)
	loco.add_blend_point(_play(&"walk"), float(data["walk_speed"]))
	loco.add_blend_point(_play(&"run"), float(data["sprint_speed"]))
	tree.add_node(&"loco", loco, Vector2(0, 0))
	var crouch_loco := AnimationNodeBlendSpace1D.new()
	crouch_loco.min_space = 0.0
	crouch_loco.max_space = float(data["crouch_speed"])
	crouch_loco.add_blend_point(_play(&"crouch_idle"), 0.0)
	crouch_loco.add_blend_point(_play(&"crouch_walk"), float(data["crouch_speed"]))
	tree.add_node(&"crouch_loco", crouch_loco, Vector2(0, 200))
	tree.add_node(&"fall", _play(&"fall"), Vector2(200, 300))
	tree.add_node(&"slide_pose", _play(&"slide"), Vector2(400, 300))
	for blend in [[&"crouch", Vector2(200, 100)], [&"air", Vector2(400, 100)], [&"slide", Vector2(600, 100)]]:
		tree.add_node(blend[0], AnimationNodeBlend2.new(), blend[1])
	tree.connect_node(&"crouch", 0, &"loco")
	tree.connect_node(&"crouch", 1, &"crouch_loco")
	tree.connect_node(&"air", 0, &"crouch")
	tree.connect_node(&"air", 1, &"fall")
	tree.connect_node(&"slide", 0, &"air")
	tree.connect_node(&"slide", 1, &"slide_pose")
	tree.connect_node(&"output", 0, &"slide")
	return tree


func _play(clip: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	return node


# --- Helpers -----------------------------------------------------------------------------

func _at(pos: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, pos)


func _bone(bone_name: String, parent: String, local_rest: Transform3D) -> void:
	var i := _skel.add_bone(bone_name)
	if not parent.is_empty():
		_skel.set_bone_parent(i, _skel.find_bone(parent))
	_skel.set_bone_rest(i, local_rest)
	_skel.reset_bone_pose(i)


func _bone_global(bone_name: String, parent: String, global_rest: Transform3D) -> void:
	var parent_global := _skel.get_bone_global_rest(_skel.find_bone(parent))
	_bone(bone_name, parent, parent_global.affine_inverse() * global_rest)


## Two-bone IK: where the elbow goes for a hand at `hand`, bending toward `pole`.
func _elbow(shoulder: Vector3, hand: Vector3, pole: Vector3) -> Vector3:
	var to_hand := hand - shoulder
	var reach := minf(to_hand.length(), UPPER_ARM + FOREARM - 0.001)
	var axis := to_hand.normalized()
	# Distance along the shoulder-hand line to the elbow's foot, and its height off it.
	var along := (UPPER_ARM * UPPER_ARM - FOREARM * FOREARM + reach * reach) / (2.0 * reach)
	var lift := sqrt(maxf(UPPER_ARM * UPPER_ARM - along * along, 0.0))
	var bend := (pole - axis * pole.dot(axis)).normalized()
	return shoulder + axis * along + bend * lift


## A basis whose +Y points along `dir`.
func _along(dir: Vector3) -> Basis:
	var d := dir.normalized()
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.FORWARD
	return Basis.looking_at(d, up) * Basis(Vector3.RIGHT, -PI / 2.0)


## Every vertex added from here on moves with `bone` alone.
func _weight(st: SurfaceTool, bone: String) -> void:
	st.set_bones(PackedInt32Array([_skel.find_bone(bone), 0, 0, 0]))
	st.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))


## A box placed in `bone`'s rest space.
func _box(st: SurfaceTool, bone: String, size: Vector3, bevel: float, offset: Vector3, colour: Color) -> void:
	var xf := _skel.get_bone_global_rest(_skel.find_bone(bone)) * _at(offset)
	LowPoly.chamfer_box(st, size, bevel, xf, colour)


## A limb segment from `bone`'s head to its child's head.
func _limb(st: SurfaceTool, bone: String, thickness: float, colour: Color) -> void:
	var i := _skel.find_bone(bone)
	var from := _skel.get_bone_global_rest(i).origin
	var to := _skel.get_bone_global_rest(i + 1).origin
	var dir := to - from
	var basis := Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.FORWARD)
	LowPoly.chamfer_box(st, Vector3(thickness, thickness, dir.length() + thickness * 0.5), thickness * 0.3, Transform3D(basis, from + dir * 0.5), colour)

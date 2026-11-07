extends SceneTree
## Builds modules/player/scenes/player_body.tscn: a low-poly soldier with realistic
## proportions as one skinned mesh on a Skeleton3D, with an AnimationPlayer of clips (idle,
## walk, run, crouch, slide, fall) and an AnimationTree that blends them. Bones use
## humanoid names (Hips, Spine, Chest, Shoulders, Head, UpperArm_R ...) so a rigged model
## from the art teammate can replace this. Feet at the origin, facing -Z, 1.8 m tall.
##
## Low poly, not cartoon: a head about an eighth of the height, long legs, a torso no
## wider than the shoulders, tapered faceted limbs and small bevels so edges stay crisp.
## Gear (plate carrier, pouches, knee pads, headset) carries the soldier read.
##
## Every part is weighted fully to one bone: rigid segments keep joints from smearing.
## Clips are generated from pose functions sampled over the cycle; grounded clips solve
## the hip height per key so the lower boot sole touches the ground.

const OUT := "res://modules/player/scenes/player_body.tscn"
const PLAYER_DATA := "res://modules/player/data/player.json"
const AIM_SCRIPT := "res://modules/player/scripts/body_aim_modifier.gd"
const HAND_IK_SCRIPT := "res://modules/player/scripts/hand_ik_modifier.gd"

## Muted, real-world kit colours.
const SHIRT := Color(0.3, 0.32, 0.25)
const TROUSERS := Color(0.31, 0.33, 0.27)
const VEST := Color(0.4, 0.37, 0.28)
const POUCH := Color(0.35, 0.32, 0.24)
const STRAP := Color(0.13, 0.13, 0.12)
const SKIN := Color(0.7, 0.54, 0.43)
const HELMET := Color(0.32, 0.33, 0.27)
const GLOVE := Color(0.14, 0.13, 0.12)
const BOOT := Color(0.21, 0.17, 0.13)
const SOLE := Color(0.09, 0.09, 0.09)
const PAD := Color(0.2, 0.21, 0.18)
## Faceted limbs: enough sides to read round at distance, few enough to stay low poly.
const LIMB_SIDES := 7

const HIPS_HEIGHT := 1.0
## Leg chain: hip joint below the Hips bone, thigh length, knee to boot sole.
const HIP_JOINT := 0.07
const THIGH := 0.43
const SHIN := 0.5
## Travel per full walk cycle (two steps), so the feet do not skate at the matching speed.
const WALK_STRIDE := 2.6
const RUN_STRIDE := 3.6
const CROUCH_STRIDE := 1.6
const KEYS_PER_CYCLE := 16

## Rifle hold, in chest space. The rifle sits right of centre with its stock in the right
## shoulder; the hands go where the rifle mesh has its pistol grip and handguard, and the
## elbows are solved from the arm lengths, pointing down and out.
const RIFLE_AT := Vector3(0.12, 0.13, -0.34)
const GRIP := RIFLE_AT + Vector3(0.0, -0.085, 0.12)
const FORE := RIFLE_AT + Vector3(-0.035, -0.005, -0.2)
const R_SHOULDER := Vector3(0.2, 0.17, 0)
# Pushed forward: the support shoulder reaches toward the handguard when shooting.
const L_SHOULDER := Vector3(-0.2, 0.17, -0.03)
const UPPER_ARM := 0.31
const FOREARM := 0.31
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
	# Then the hands reach for the held gun's grip points.
	var hand_ik := SkeletonModifier3D.new()
	hand_ik.name = "HandIK"
	hand_ik.set_script(load(HAND_IK_SCRIPT))
	_skel.add_child(hand_ik)

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
	_bone("Spine", "Hips", _at(Vector3(0, 0.1, 0)))
	_bone("Chest", "Spine", _at(Vector3(0, 0.2, 0)))
	# At the top of the neck, so the head nods about the right point.
	_bone("Head", "Chest", _at(Vector3(0, 0.27, 0)))
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
		_bone("UpperLeg_" + side[0], "Hips", _at(Vector3(side[1] * 0.1, -HIP_JOINT, 0)))
		_bone("LowerLeg_" + side[0], "UpperLeg_" + side[0], _at(Vector3(0, -THIGH, 0)))


func _build_mesh() -> void:
	var st := LowPoly.begin()
	_weight(st, "Hips")
	_box(st, "Hips", Vector3(0.32, 0.2, 0.21), 0.02, Vector3(0, -0.02, 0), TROUSERS)
	_box(st, "Hips", Vector3(0.34, 0.05, 0.23), 0.01, Vector3(0, 0.06, 0), STRAP)
	for x in [-0.17, 0.17]:
		_box(st, "Hips", Vector3(0.06, 0.1, 0.08), 0.01, Vector3(x, 0.02, -0.03), POUCH)

	_weight(st, "Spine")
	_box(st, "Spine", Vector3(0.3, 0.22, 0.19), 0.02, Vector3(0, 0.08, 0), SHIRT)

	_weight(st, "Chest")
	_box(st, "Chest", Vector3(0.36, 0.3, 0.23), 0.025, Vector3(0, 0.04, 0), SHIRT)
	_box(st, "Chest", Vector3(0.38, 0.08, 0.19), 0.025, Vector3(0, 0.15, 0), SHIRT)
	# Plate carrier: front and back plates, side panels, cummerbund, straps and pouches.
	_box(st, "Chest", Vector3(0.3, 0.3, 0.05), 0.012, Vector3(0, 0.02, -0.135), VEST)
	_box(st, "Chest", Vector3(0.26, 0.26, 0.022), 0.006, Vector3(0, 0.03, 0.123), VEST)
	for x in [-0.17, 0.17]:
		_box(st, "Chest", Vector3(0.04, 0.2, 0.2), 0.01, Vector3(x, -0.03, 0), VEST)
		_box(st, "Chest", Vector3(0.05, 0.03, 0.26), 0.008, Vector3(x * 0.6, 0.17, 0), STRAP)
	_box(st, "Chest", Vector3(0.35, 0.08, 0.27), 0.012, Vector3(0, -0.1, 0), VEST)
	for x in [-0.085, 0.0, 0.085]:
		_box(st, "Chest", Vector3(0.08, 0.14, 0.08), 0.01, Vector3(x, -0.07, -0.195), POUCH)
	_box(st, "Chest", Vector3(0.2, 0.08, 0.04), 0.008, Vector3(0, 0.1, -0.175), POUCH)
	_box(st, "Chest", Vector3(0.2, 0.05, 0.2), 0.01, Vector3(0, 0.2, 0), SHIRT.darkened(0.1))
	_tube(st, "Chest", 0.19, 0.29, 0.056, 0.05, SKIN)

	_weight(st, "Head")
	_box(st, "Head", Vector3(0.17, 0.21, 0.2), 0.03, Vector3(0, 0.1, -0.005), SKIN)
	_box(st, "Head", Vector3(0.03, 0.045, 0.03), 0.006, Vector3(0, 0.07, -0.11), SKIN.darkened(0.12))
	for x in [-0.036, 0.036]:
		_box(st, "Head", Vector3(0.03, 0.014, 0.01), 0.002, Vector3(x, 0.095, -0.103), STRAP)
	# Helmet sits close on the head, with a rim, a mount at the front and a headset under it.
	_box(st, "Head", Vector3(0.21, 0.11, 0.24), 0.04, Vector3(0, 0.18, 0.005), HELMET)
	_box(st, "Head", Vector3(0.22, 0.03, 0.25), 0.01, Vector3(0, 0.135, 0.005), HELMET.darkened(0.15))
	_box(st, "Head", Vector3(0.045, 0.04, 0.02), 0.005, Vector3(0, 0.17, -0.125), STRAP)
	for x in [-0.1, 0.1]:
		_box(st, "Head", Vector3(0.04, 0.07, 0.07), 0.01, Vector3(x, 0.085, 0.01), STRAP)
		_box(st, "Head", Vector3(0.012, 0.09, 0.012), 0.002, Vector3(x * 0.85, 0.03, -0.03), STRAP)

	# The arms are their own mesh: in first person the player sees their own arms holding
	# the rifle while the rest of the body only casts a shadow.
	var arms := LowPoly.begin()
	for side in ["R", "L"]:
		_weight(arms, "UpperArm_" + side)
		_tube(arms, "UpperArm_" + side, 0.0, UPPER_ARM, 0.055, 0.046, SHIRT)
		_box(arms, "UpperArm_" + side, Vector3(0.11, 0.1, 0.11), 0.02, Vector3(0, 0.03, 0), SHIRT.darkened(0.08))
		_weight(arms, "LowerArm_" + side)
		_tube(arms, "LowerArm_" + side, 0.0, FOREARM - 0.02, 0.046, 0.039, SHIRT)
		_weight(arms, "Hand_" + side)
		_box(arms, "Hand_" + side, Vector3(0.09, 0.11, 0.06), 0.014, Vector3(0, 0.02, 0), GLOVE)

	for side in [["L", -1.0], ["R", 1.0]]:
		var upper: String = "UpperLeg_" + side[0]
		var lower: String = "LowerLeg_" + side[0]
		_weight(st, upper)
		_tube(st, upper, 0.0, -THIGH * 0.45, 0.092, 0.088, TROUSERS)
		_tube(st, upper, -THIGH * 0.45, -THIGH, 0.088, 0.062, TROUSERS)
		_box(st, upper, Vector3(0.03, 0.12, 0.1), 0.006, Vector3(side[1] * 0.075, -0.22, 0), TROUSERS.darkened(0.1))
		_weight(st, lower)
		_box(st, lower, Vector3(0.1, 0.11, 0.04), 0.012, Vector3(0, -0.01, -0.065), PAD)
		_tube(st, lower, 0.0, -0.16, 0.06, 0.068, TROUSERS)
		_tube(st, lower, -0.16, -0.39, 0.068, 0.047, TROUSERS)
		_box(st, lower, Vector3(0.09, 0.12, 0.13), 0.015, Vector3(0, -0.43, 0.0), BOOT)
		_box(st, lower, Vector3(0.088, 0.075, 0.13), 0.02, Vector3(0, -0.4575, -0.1), BOOT)
		_box(st, lower, Vector3(0.095, 0.022, 0.25), 0.004, Vector3(0, -SHIN + 0.011, -0.045), SOLE)

	var skin := _skel.create_skin_from_rest_transforms()
	var material := LowPoly.material(0.85)
	for part in [["Mesh", st], ["Arms", arms]]:
		var inst := MeshInstance3D.new()
		inst.name = part[0]
		inst.mesh = LowPoly.finish(part[1], material)
		inst.skin = skin
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
		"UpperLeg_L": Vector3(8, 0, -7), "LowerLeg_L": Vector3(-10, 0, 0), "UpperLeg_R": Vector3(-6, 0, 6), "LowerLeg_R": Vector3(-6, 0, 0)}


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
		"UpperLeg_L": Vector3(72, 0, -6), "LowerLeg_L": Vector3(-112, 0, 0), "UpperLeg_R": Vector3(50, 0, 6), "LowerLeg_R": Vector3(-105, 0, 0)}


func _crouch_walk(p: float) -> Dictionary:
	var pose := {"Spine": Vector3(-28, 0, 0), "Chest": Vector3(-10, 0, 0), "Head": Vector3(32, 0, 0)}
	for side in [["L", 0.0], ["R", 0.5]]:
		var q := TAU * (p + float(side[1]))
		pose["UpperLeg_" + side[0]] = Vector3(58 + 20 * cos(q), 0, 0)
		pose["LowerLeg_" + side[0]] = Vector3(-(95 + 25 * maxf(0.0, -sin(q))), 0, 0)
	return pose


func _slide(_p: float) -> Dictionary:
	# Leading leg out straight, the other folded under, leaning back into the slide.
	return {"Spine": Vector3(28, 0, 0), "Chest": Vector3(8, 0, 0), "Head": Vector3(-30, 0, 0),
		"UpperLeg_L": Vector3(70, 0, 0), "LowerLeg_L": Vector3(-5, 0, 0), "UpperLeg_R": Vector3(30, 0, 10), "LowerLeg_R": Vector3(-125, 0, 0)}


func _fall(_p: float) -> Dictionary:
	# Knees pulled up, feet off the ground: in the air, not mid-stride.
	return {"Spine": Vector3(-10, 0, 0), "Head": Vector3(10, 0, 0), "airborne": true,
		"UpperLeg_L": Vector3(118, 0, -8), "LowerLeg_L": Vector3(-115, 0, 0), "UpperLeg_R": Vector3(95, 0, 8), "LowerLeg_R": Vector3(-100, 0, 0)}


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


## A faceted, tapered tube along `bone`'s Y axis from `from_y` to `to_y`, in bone space.
func _tube(st: SurfaceTool, bone: String, from_y: float, to_y: float, r_from: float, r_to: float, colour: Color) -> void:
	var xf := _skel.get_bone_global_rest(_skel.find_bone(bone)) * _at(Vector3(0, (from_y + to_y) * 0.5, 0))
	# The cylinder's first radius is at its lower end.
	var low_r := r_from if from_y < to_y else r_to
	var high_r := r_to if from_y < to_y else r_from
	LowPoly.cylinder(st, low_r, absf(to_y - from_y), LIMB_SIDES, xf, colour, high_r)

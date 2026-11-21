class_name PlayerBodyAnimator
extends Node
## Client-side: feeds the third-person body's AnimationTree from the player's state (speed,
## crouch, slide, airborne, climbing a ladder) and its aim modifier from the look pitch and
## aiming down sights. The clips and the blend tree come from the body builder. Cosmetic only; the
## server never runs it.

## How quickly blends follow the state, per second; high enough to feel immediate, low
## enough that a one-frame flicker (a bump while walking) does not pop the pose.
const BLEND_RATE := 12.0
const AIM_RATE := 15.0
## Metres climbed per full climb cycle: each hand and foot one rung (0.3 m apart) up. The
## climb clip and the hands advance by how far the body has risen, so they keep pace with
## any climbing speed, run backwards climbing down and hold when the climber stops.
const CLIMB_STRIDE := 0.6
## Hands on the ladder's rails, in the Shoulders bone's space (+x right, +y up, -z ahead):
## how far out each rail is, how far ahead of the chest, and the lowest and highest grip.
const RAIL_HALF := 0.22
const RAIL_AHEAD := -0.34
const GRIP_LOW := 0.1
const GRIP_HIGH := 0.4
## Share of a cycle each hand holds its rung (sinking past the shoulders as the body rises,
## so it stays put on the ladder); for the rest it reaches up to the next one. With the
## stride, (GRIP_HIGH - GRIP_LOW) equals the climb while holding.
const GRIP_HOLD := 0.5
## How far a reaching hand comes back off the rungs at the top of its arc, metres.
const REACH_CLEAR := 0.08
## How quickly the body turns to face the ladder and back, per second.
const TURN_RATE := 10.0
## The held gun's turn on its socket while climbing (radians, Euler): muzzle down and across
## the body, so it hangs clear of the rungs while both hands are on the rails.
const SLUNG := Vector3(-1.2, 0.35, 0.0)

## Never closer to the eye than the camera's near plane plus this, or the sight's rear is cut.
const NEAR_MARGIN := 0.01

var player: PlayerController
## How far from the eye the held gun should sit, as a share of where it was set up to sit:
## below 1 nearer, for a view wider than the default, so the sight picture keeps its size on
## screen; above 1 is not followed (see _update_ads). The local camera feel sets it; everyone
## else's body stays at 1.
var view_scale := 1.0

var _tree: AnimationTree
var _aim: Node
var _hand_ik: Node
var _head: Node3D
var _body: Node3D
var _crouch := 0.0
var _air := 0.0
var _slide := 0.0
var _climb := 0.0
## How far through the climb cycle the body is (whole cycles count up the ladder).
var _climb_phase := 0.0
var _climb_length := 1.0
var _ads := 0.0
var _camera: Node3D
## The first-person hip point the body was set up with; zero in third person.
var _default_hip := Vector3.ZERO
var _hip_read := false


## How far into aiming down sights the body is, 0 to 1. The camera reads it for its zoom.
func ads_amount() -> float:
	return _ads


## How far into the climb pose the body is, 0 to 1.
func climb_amount() -> float:
	return _climb


## How far into the falling pose the body is, 0 to 1.
func air_amount() -> float:
	return _air


## The held weapon's sight zoom (1 = none), from the `Sight` marker's `zoom` meta.
func sight_zoom() -> float:
	var sight := _sight_marker()
	return float(sight.get_meta(&"zoom", 1.0)) if sight != null else 1.0


## How much the held weapon's scope magnifies (1 for open sights), from the `Sight`
## marker's `magnification` meta. Aiming turns slower through a scope by this much.
func sight_magnification() -> float:
	var sight := _sight_marker()
	return float(sight.get_meta(&"magnification", 1.0)) if sight != null else 1.0


func _ready() -> void:
	_body = player.get_node("Body")
	var body: Node = _body
	_tree = body.get_node("AnimationTree")
	var anims := body.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anims != null and anims.has_animation(&"climb"):
		_climb_length = anims.get_animation(&"climb").length
	_aim = body.get_node("Skeleton/Aim")
	_hand_ik = body.get_node_or_null("Skeleton/HandIK")
	_head = player.get_node("Head")
	_camera = player.get_node("Head/Camera")
	_tree.active = true


func _process(delta: float) -> void:
	var prof := Prof.start()
	_process_tick(delta)
	Prof.stop(&"player/player_body_animator:frame", prof)


func _process_tick(delta: float) -> void:
	var blend := 1.0 - exp(-BLEND_RATE * delta)
	var speed := player.horizontal_speed()
	var sliding := player.is_sliding()
	var traversing := player.mode == PlayerController.Mode.MANTLE or player.mode == PlayerController.Mode.VAULT
	var on_ladder := player.climbing
	_crouch = lerpf(_crouch, 1.0 if player.intent().crouch else 0.0, blend)
	_air = lerpf(_air, 1.0 if player.airborne() or traversing else 0.0, blend)
	_slide = lerpf(_slide, 1.0 if sliding else 0.0, blend)
	_climb = lerpf(_climb, 1.0 if on_ladder else 0.0, blend)
	if on_ladder:
		_climb_phase += player.velocity.y * delta / CLIMB_STRIDE
	_tree.set(&"parameters/climb/blend_amount", _climb)
	_tree.set(&"parameters/climb_seek/seek_request", fposmod(_climb_phase, 1.0) * _climb_length)
	_face_ladder(delta)
	var socket := PlayerBody.weapon_socket(player)
	if socket != null:
		socket.rotation = socket.rotation.lerp(SLUNG if on_ladder else Vector3.ZERO, blend)
	_tree.set(&"parameters/loco/blend_position", speed)
	_tree.set(&"parameters/crouch_loco/blend_position", speed)
	_tree.set(&"parameters/crouch/blend_amount", _crouch)
	_tree.set(&"parameters/air/blend_amount", _air)
	_tree.set(&"parameters/slide/blend_amount", _slide)
	var pitch: float = _aim.get(&"pitch")
	# On a ladder the body faces the rungs whatever the view does.
	var aim_pitch := 0.0 if on_ladder else _head.rotation.x
	_aim.set(&"pitch", lerpf(pitch, aim_pitch, 1.0 - exp(-AIM_RATE * delta)))
	# The body rolls further than the camera so the visible head ends up where the eye went.
	_aim.set(&"lean", player.lean_amount() * deg_to_rad(float(player.config.get("lean_body_degrees", 0.0))))
	_update_ads(delta)
	_update_hands()


## Eases into and out of aiming over `ads_seconds`, and tells the aim modifier where the
## held weapon's sight is so it can bring it to the eye.
func _update_ads(delta: float) -> void:
	var sight := _sight_marker()
	var aiming := player.intent().aim and sight != null and not player.is_sliding() and not player.climbing
	# The gun's own ADS time (from its parts' ergonomics) when it has one.
	var seconds := float(sight.get_meta(&"ads_seconds", player.config["ads_seconds"])) if sight != null else float(player.config["ads_seconds"])
	var step := delta / maxf(seconds, 0.01)
	_ads = move_toward(_ads, 1.0 if aiming else 0.0, step)
	# Smoothstep, so the sight eases onto the eye instead of arriving at full speed.
	var eased := _ads * _ads * (3.0 - 2.0 * _ads)
	_aim.set(&"ads", eased)
	_aim.set(&"eye", _camera)
	# Scopes sit closer to the eye than open sights; the optic says how close.
	var relief := float(player.config["ads_eye_relief"])
	if sight != null:
		relief = float(sight.get_meta(&"eye_relief", relief))
	var nearest := (_camera as Camera3D).near + NEAR_MARGIN if _camera is Camera3D else 0.0
	# Only ever nearer: the arms already reach as far as the gun was set up to sit (a pistol
	# at arm's length), so a view narrower than the default shows the gun a little bigger.
	var scale := minf(view_scale, 1.0)
	_aim.set(&"eye_relief", maxf(relief * scale, minf(relief, nearest)))
	if not _hip_read:
		_hip_read = true
		_default_hip = _aim.get(&"hip_sight")
	# First person only: a gun can ask to be held elsewhere at the hip (a pistol, further out).
	if _default_hip != Vector3.ZERO:
		var hip := _default_hip
		if sight != null and sight.has_meta(&"hip_sight"):
			hip = sight.get_meta(&"hip_sight")
		# Only the distance changes: the same sideways and downward offset then lands on the
		# same spot on screen at any field of view.
		hip.z = minf(hip.z * scale, maxf(hip.z, -nearest))
		_aim.set(&"hip_sight", hip)
	if sight != null:
		# The sight in the space of the bone the weapon hangs from (the socket's parent is
		# that bone's attachment). Both globals are from this frame, so the lag cancels out.
		var socket := PlayerBody.weapon_socket(player)
		_aim.set(&"sight", socket.transform * (socket.global_transform.affine_inverse() * sight.global_position))


## Tells the hand IK where the held gun wants each hand (its `GripR` / `GripL` markers), in
## the Shoulders bone's space like the sight, so the hands stay on the gun as it moves.
func _update_hands() -> void:
	if _hand_ik == null:
		return
	if player.climbing:
		_hand_ik.set(&"targets", rail_grips(_climb_phase))
		return
	var socket := PlayerBody.weapon_socket(player)
	var targets := {}
	if socket != null:
		for side: StringName in [&"R", &"L"]:
			var marker := socket.find_child("Grip" + String(side), true, false) as Node3D
			if marker != null:
				targets[side] = socket.transform * (socket.global_transform.affine_inverse() * marker.global_position)
	_hand_ik.set(&"targets", targets)


func _sight_marker() -> Node3D:
	var socket := PlayerBody.weapon_socket(player)
	return socket.find_child("Sight", true, false) as Node3D if socket != null else null


## Turns the body (not the view) to face the ladder being climbed, and back once off it.
func _face_ladder(delta: float) -> void:
	var into := player.ladder_into()
	var yaw := 0.0
	if into != Vector3.ZERO:
		var local := player.global_basis.inverse() * into
		# The body faces its -Z.
		yaw = atan2(-local.x, -local.z)
	_body.rotation.y = lerp_angle(_body.rotation.y, yaw, 1.0 - exp(-TURN_RATE * delta))


## Where each hand grips the rails at climb cycle `phase`, in the Shoulders bone's space: one
## holds while the other reaches up, the right reaching as the left foot lifts.
static func rail_grips(phase: float) -> Dictionary:
	return {&"R": _grip(phase + 0.25, RAIL_HALF), &"L": _grip(phase + 0.75, -RAIL_HALF)}


static func _grip(phase: float, x: float) -> Vector3:
	var u := fposmod(phase, 1.0)
	var reach := 1.0 - GRIP_HOLD
	if u < reach:
		var t := u / reach
		var eased := t * t * (3.0 - 2.0 * t)
		return Vector3(x, lerpf(GRIP_LOW, GRIP_HIGH, eased), RAIL_AHEAD + REACH_CLEAR * sin(PI * t))
	return Vector3(x, lerpf(GRIP_HIGH, GRIP_LOW, (u - reach) / GRIP_HOLD), RAIL_AHEAD)

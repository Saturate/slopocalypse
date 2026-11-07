class_name PlayerBodyAnimator
extends Node
## Client-side: feeds the third-person body's AnimationTree from the player's state (speed,
## crouch, slide, airborne) and its aim modifier from the look pitch and aiming down
## sights. The clips and the blend tree come from the body builder. Cosmetic only; the
## server never runs it.

## How quickly blends follow the state, per second; high enough to feel immediate, low
## enough that a one-frame flicker (a bump while walking) does not pop the pose.
const BLEND_RATE := 12.0
const AIM_RATE := 15.0
## Vertical speed that counts as airborne where floor contact is unknown (remote copies).
const AIRBORNE_SPEED := 1.5

var player: PlayerController

var _tree: AnimationTree
var _aim: Node
var _head: Node3D
var _crouch := 0.0
var _air := 0.0
var _slide := 0.0
var _ads := 0.0
var _camera: Node3D


## How far into aiming down sights the body is, 0 to 1. The camera reads it for its zoom.
func ads_amount() -> float:
	return _ads


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
	var body := player.get_node("Body")
	_tree = body.get_node("AnimationTree")
	_aim = body.get_node("Skeleton/Aim")
	_head = player.get_node("Head")
	_camera = player.get_node("Head/Camera")
	_tree.active = true


func _process(delta: float) -> void:
	var blend := 1.0 - exp(-BLEND_RATE * delta)
	var speed := player.horizontal_speed()
	var sliding := player.is_sliding()
	var climbing := player.mode == PlayerController.Mode.MANTLE or player.mode == PlayerController.Mode.VAULT
	_crouch = lerpf(_crouch, 1.0 if player.intent().crouch else 0.0, blend)
	_air = lerpf(_air, 1.0 if _airborne() or climbing else 0.0, blend)
	_slide = lerpf(_slide, 1.0 if sliding else 0.0, blend)
	_tree.set(&"parameters/loco/blend_position", speed)
	_tree.set(&"parameters/crouch_loco/blend_position", speed)
	_tree.set(&"parameters/crouch/blend_amount", _crouch)
	_tree.set(&"parameters/air/blend_amount", _air)
	_tree.set(&"parameters/slide/blend_amount", _slide)
	var pitch: float = _aim.get(&"pitch")
	_aim.set(&"pitch", lerpf(pitch, _head.rotation.x, 1.0 - exp(-AIM_RATE * delta)))
	_update_ads(delta)


## Eases into and out of aiming over `ads_seconds`, and tells the aim modifier where the
## held weapon's sight is so it can bring it to the eye.
func _update_ads(delta: float) -> void:
	var sight := _sight_marker()
	var aiming := player.intent().aim and sight != null and not player.is_sliding()
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
	_aim.set(&"eye_relief", relief)
	if sight != null:
		# The sight in the space of the bone the weapon hangs from (the socket's parent is
		# that bone's attachment). Both globals are from this frame, so the lag cancels out.
		var socket := PlayerBody.weapon_socket(player)
		_aim.set(&"sight", socket.transform * (socket.global_transform.affine_inverse() * sight.global_position))


func _sight_marker() -> Node3D:
	var socket := PlayerBody.weapon_socket(player)
	return socket.find_child("Sight", true, false) as Node3D if socket != null else null


## The server and solo simulate the body and know floor contact; remote copies only get
## the synced velocity.
func _airborne() -> bool:
	if player.is_physics_processing():
		return not player.is_on_floor()
	return absf(player.velocity.y) > AIRBORNE_SPEED

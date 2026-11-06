class_name PlayerBodyAnimator
extends Node
## Client-side procedural animation for the third-person body: legs swing with speed,
## knees bend on the back swing, crouch and slide lower the hips, and the chest follows the
## aim pitch. Cosmetic only; the server never runs it.

const SWING := deg_to_rad(40.0)
const KNEE := deg_to_rad(45.0)

var player: PlayerController

var _body: Node3D
var _hips: Node3D
var _chest: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _hips_rest: float
var _distance := 0.0
var _crouch := 0.0


func _ready() -> void:
	_body = player.get_node("Body")
	_hips = _body.get_node("Hips")
	_chest = _hips.get_node("Spine/Chest")
	_head = player.get_node("Head")
	_hips_rest = _hips.position.y
	for side in ["L", "R"]:
		_legs.append(_hips.get_node("UpperLeg_" + side))
		_knees.append(_hips.get_node("UpperLeg_%s/LowerLeg_%s" % [side, side]))


func _process(delta: float) -> void:
	var speed := player.horizontal_speed() if player.is_on_floor() else 0.0
	var moving := player.mode == PlayerController.Mode.NORMAL
	_distance += speed * delta * (1.0 if moving else 0.0)
	# Full stride already at walking pace; sprinting only adds a little more.
	var strength := clampf(speed / float(player.config["walk_speed"]), 0.0, 1.25)
	# A stride is about two body lengths of travel per full leg cycle.
	var phase := _distance / 1.6 * TAU

	var low := player.intent().crouch or player.is_sliding()
	_crouch = lerpf(_crouch, 1.0 if low else 0.0, 1.0 - exp(-10.0 * delta))
	var drop := (float(player.config["stand_height"]) - float(player.config["crouch_height"])) * _crouch
	_hips.position.y = _hips_rest - drop

	for i in 2:
		var side_phase := phase + PI * i
		var swing := sin(side_phase) * SWING * strength
		# Positive X rotation swings a foot forward (-Z); knees only ever bend backward.
		var knee := -maxf(0.0, -cos(side_phase)) * KNEE * strength
		# Crouching folds the legs so the feet stay on the ground as the hips drop.
		_legs[i].rotation.x = lerpf(swing, deg_to_rad(70.0), _crouch)
		_knees[i].rotation.x = lerpf(knee, -deg_to_rad(110.0), _crouch)

	# Positive X tips the chest's top backward: leaning back into the slide.
	var slide_lean := deg_to_rad(35.0) if player.is_sliding() else 0.0
	# The chest follows most of the aim pitch so the held rifle points where the player looks.
	_chest.rotation.x = lerpf(_chest.rotation.x, _head.rotation.x * 0.8 + slide_lean, 1.0 - exp(-15.0 * delta))

class_name PlayerBodyAnimator
extends Node
## Client-side: feeds the third-person body's AnimationTree from the player's state (speed,
## crouch, slide, airborne) and its aim modifier from the look pitch. The clips and the
## blend tree come from the body builder. Cosmetic only; the server never runs it.

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


func _ready() -> void:
	var body := player.get_node("Body")
	_tree = body.get_node("AnimationTree")
	_aim = body.get_node("Skeleton/Aim")
	_head = player.get_node("Head")
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


## The server and solo simulate the body and know floor contact; remote copies only get
## the synced velocity.
func _airborne() -> bool:
	if player.is_physics_processing():
		return not player.is_on_floor()
	return absf(player.velocity.y) > AIRBORNE_SPEED

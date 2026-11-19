class_name BoltCycle
extends Node
## Client only: the firing hand works a bolt-action's bolt once after a shot, on the gun in
## someone's hands. The bolt part turns its handle up, slides back and forward and turns
## down, and the gun's `GripR` marker (where the hand IK puts the right hand) goes to the
## bolt knob and back. Cosmetic: the server's rules decide when the gun can fire again, over
## the same `cycle_seconds`.
##
## Phases as shares of the cycle; the audio module's bolt sound is laid out for these.

const HAND_OFF := 0.12
const LIFT := 0.3
const BACK := 0.42
const FORWARD := 0.58
const DOWN := 0.72
const LOCKED := 0.84
const HAND_BACK := 0.97
const LIFT_RADIANS := deg_to_rad(65.0)
## How far the bolt slides back, metres.
const THROW := 0.075

var seconds := 1.0

var _t := 0.0
var _bolt: Node3D
var _bolt_rest: Transform3D
var _grip: Node3D
var _grip_rest: Vector3
## The knob in the bolt's own space, from the gun's `BoltKnob` marker.
var _knob := Vector3.ZERO


## Starts a cycle on `gun` (an assembled gun with a `bolt_handle` part), replacing one that is
## still running so the parts start from rest.
static func start(gun: Node3D, cycle_seconds: float) -> BoltCycle:
	var old := gun.get_node_or_null("BoltCycle") as BoltCycle
	if old != null:
		old.finish()
		gun.remove_child(old)
		old.queue_free()
	var bolt := gun.get_node_or_null("bolt_handle") as Node3D
	if bolt == null:
		return null
	var cycle := BoltCycle.new()
	cycle.name = "BoltCycle"
	cycle.seconds = maxf(cycle_seconds, 0.05)
	cycle._bolt = bolt
	cycle._bolt_rest = bolt.transform
	cycle._grip = gun.get_node_or_null("GripR") as Node3D
	if cycle._grip != null:
		cycle._grip_rest = cycle._grip.position
	var knob := gun.get_node_or_null("BoltKnob") as Node3D
	if knob != null:
		cycle._knob = bolt.transform.affine_inverse() * knob.position
	gun.add_child(cycle)
	return cycle


func _process(delta: float) -> void:
	_t += delta / seconds
	if _t >= 1.0:
		finish()
		queue_free()
		return
	pose(_t)


## Puts the bolt and the hand where they are `share` of the way through the cycle.
func pose(share: float) -> void:
	var lift := _ramp(share, LIFT, BACK) - _ramp(share, DOWN, LOCKED)
	var slide := _ramp(share, BACK, FORWARD - 0.04) - _ramp(share, FORWARD, DOWN - 0.04)
	var bolt := _bolt_rest * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, THROW * slide)) * Transform3D(Basis(Vector3.BACK, LIFT_RADIANS * lift), Vector3.ZERO)
	_bolt.transform = bolt
	if _grip != null:
		var on_knob := _ramp(share, HAND_OFF, LIFT) - _ramp(share, LOCKED, HAND_BACK)
		_grip.position = _grip_rest.lerp(bolt * _knob, on_knob)


## Everything back at rest.
func finish() -> void:
	if is_instance_valid(_bolt):
		_bolt.transform = _bolt_rest
	if is_instance_valid(_grip):
		_grip.position = _grip_rest


## 0 before `from`, 1 after `to`, eased between.
static func _ramp(t: float, from: float, to: float) -> float:
	var x := clampf((t - from) / (to - from), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

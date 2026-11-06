class_name PlayerController
extends CharacterBody3D
## First-person movement driven only by PlayerIntent: walk, sprint, crouch, jump, look.

const CONFIG := "res://modules/player/data/player.json"
const REQUIRED := {
	"walk_speed": TYPE_FLOAT,
	"sprint_speed": TYPE_FLOAT,
	"crouch_speed": TYPE_FLOAT,
	"acceleration": TYPE_FLOAT,
	"air_control": TYPE_FLOAT,
	"jump_velocity": TYPE_FLOAT,
	"stand_height": TYPE_FLOAT,
	"crouch_height": TYPE_FLOAT,
	"eye_offset": TYPE_FLOAT,
	"radius": TYPE_FLOAT,
	"mouse_sensitivity": TYPE_FLOAT,
}
const PITCH_LIMIT := deg_to_rad(89.0)

@export var intent_path: NodePath
@export var head_path: NodePath
@export var shape_path: NodePath

var config: Dictionary = {}

var _intent: PlayerIntent
var _head: Node3D
var _capsule: CapsuleShape3D
var _shape_node: CollisionShape3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	_intent = get_node(intent_path)
	_head = get_node(head_path)
	_shape_node = get_node(shape_path)
	_capsule = _shape_node.shape
	var data: Variant = Data.load_json(CONFIG)
	if data is Dictionary and Data.require(CONFIG, data, REQUIRED):
		config = data
	else:
		set_physics_process(false)
		return
	_apply_height(config["stand_height"])


func intent() -> PlayerIntent:
	return _intent


func _physics_process(delta: float) -> void:
	if _intent.consume_interact():
		# Whoever owns the thing in front of us (car, later loot) decides what happens.
		EventBus.publish(&"player.interact", {"player": self})
	var look := _intent.consume_look()
	rotate_y(-look.x)
	_head.rotation.x = clampf(_head.rotation.x - look.y, -PITCH_LIMIT, PITCH_LIMIT)

	var crouching := _intent.crouch
	_apply_height(config["crouch_height"] if crouching else config["stand_height"])

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif _intent.consume_jump() and not crouching:
		velocity.y = config["jump_velocity"]

	var speed: float = config["walk_speed"]
	if crouching:
		speed = config["crouch_speed"]
	elif _intent.sprint and _intent.move.y > 0.0:
		speed = config["sprint_speed"]
	var wish := transform.basis * Vector3(_intent.move.x, 0.0, -_intent.move.y)
	var target := wish.limit_length(1.0) * speed
	var accel: float = config["acceleration"] * (1.0 if is_on_floor() else config["air_control"])
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(Vector2(target.x, target.z), accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	move_and_slide()


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Resizes the capsule from the feet up, so crouching never pushes the body into the ground.
func _apply_height(height: float) -> void:
	if is_equal_approx(_capsule.height, height):
		return
	_capsule.height = height
	_capsule.radius = config["radius"]
	_shape_node.position.y = height / 2.0
	_head.position.y = height - float(config["eye_offset"])

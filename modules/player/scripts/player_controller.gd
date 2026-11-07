class_name PlayerController
extends CharacterBody3D
## First-person movement driven only by PlayerIntent: walk, sprint with momentum, crouch,
## slide, hop, vault low cover and mantle onto ledges. Cosmetic camera feel (FOV, bob)
## lives in PlayerCameraFeel on clients; nothing here depends on rendering.

const CONFIG := "res://modules/player/data/player.json"
const REQUIRED := {
	"walk_speed": TYPE_FLOAT,
	"sprint_speed": TYPE_FLOAT,
	"crouch_speed": TYPE_FLOAT,
	"acceleration": TYPE_FLOAT,
	"sprint_acceleration": TYPE_FLOAT,
	"ads_speed_multiplier": TYPE_FLOAT,
	"ads_seconds": TYPE_FLOAT,
	"ads_eye_relief": TYPE_FLOAT,
	"air_control": TYPE_FLOAT,
	"jump_velocity": TYPE_FLOAT,
	"fall_gravity_multiplier": TYPE_FLOAT,
	"mantle_reach": TYPE_FLOAT,
	"mantle_min_height": TYPE_FLOAT,
	"mantle_max_height": TYPE_FLOAT,
	"mantle_time": TYPE_FLOAT,
	"vault_max_height": TYPE_FLOAT,
	"vault_max_depth": TYPE_FLOAT,
	"vault_time": TYPE_FLOAT,
	"vault_clearance": TYPE_FLOAT,
	"vault_min_speed": TYPE_FLOAT,
	"slide_min_speed": TYPE_FLOAT,
	"slide_boost": TYPE_FLOAT,
	"slide_time": TYPE_FLOAT,
	"slide_friction": TYPE_FLOAT,
	"stand_height": TYPE_FLOAT,
	"crouch_height": TYPE_FLOAT,
	"eye_offset": TYPE_FLOAT,
	"radius": TYPE_FLOAT,
	"mouse_sensitivity": TYPE_FLOAT,
	"max_health": TYPE_FLOAT,
	"respawn_seconds": TYPE_FLOAT,
}
const PITCH_LIMIT := deg_to_rad(89.0)

enum Mode { NORMAL, MANTLE, VAULT, SLIDE }

@export var intent_path: NodePath
@export var head_path: NodePath
@export var shape_path: NodePath

var config: Dictionary = {}
var mode: Mode = Mode.NORMAL

var _intent: PlayerIntent
var _head: Node3D
var _capsule: CapsuleShape3D
var _shape_node: CollisionShape3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _was_crouching := false

# Traversal (mantle and vault) runs along a scripted path instead of physics.
var _path_t := 0.0
var _path_from: Vector3
var _path_over: Vector3
var _path_to: Vector3
var _path_exit_velocity := Vector3.ZERO

var _slide_left := 0.0


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
	var health := get_node_or_null("Health") as HealthComponent
	if health != null:
		health.max_health = config["max_health"]
		health.server_reset()


func intent() -> PlayerIntent:
	return _intent


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func is_mantling() -> bool:
	return mode == Mode.MANTLE


func is_vaulting() -> bool:
	return mode == Mode.VAULT


func is_sliding() -> bool:
	return mode == Mode.SLIDE


## True while the sprint key is driving speed above walking pace.
func is_sprinting() -> bool:
	return mode == Mode.NORMAL and _wants_sprint() and is_on_floor() and horizontal_speed() > float(config["walk_speed"]) + 0.1


func _physics_process(delta: float) -> void:
	if _intent.consume_interact():
		# Whoever owns the thing in front of us (car, later loot) decides what happens.
		EventBus.publish(&"player.interact", {"player": self})
		# Entering a car parks this player mid-step, which takes the body out of the physics
		# space; moving it now makes Jolt log "Parameter space is null".
		if not can_process():
			return
	if _intent.remote_look:
		# A remote client owns its aim and sends it absolute.
		rotation.y = _intent.look_yaw
		_head.rotation.x = clampf(_intent.look_pitch, -PITCH_LIMIT, PITCH_LIMIT)
	else:
		var look := _intent.consume_look()
		rotate_y(-look.x)
		_head.rotation.x = clampf(_head.rotation.x - look.y, -PITCH_LIMIT, PITCH_LIMIT)

	match mode:
		Mode.MANTLE, Mode.VAULT:
			_step_path(delta)
		Mode.SLIDE:
			_step_slide(delta)
		_:
			_step_normal(delta)
	_was_crouching = _intent.crouch


func _wants_sprint() -> bool:
	# Firing or aiming interrupts sprinting, as does moving anywhere but forward.
	return _intent.sprint and _intent.move.y > 0.0 and not _intent.fire and not _intent.aim


func _step_normal(delta: float) -> void:
	var crouching := _intent.crouch
	var crouch_pressed := crouching and not _was_crouching
	if crouch_pressed and is_on_floor() and _wants_sprint() and horizontal_speed() >= float(config["slide_min_speed"]):
		_start_slide()
		return
	_apply_height(config["crouch_height"] if crouching else config["stand_height"])

	if not is_on_floor():
		# Falling faster than rising makes jumps feel heavy instead of floaty.
		var gravity_scale: float = config["fall_gravity_multiplier"] if velocity.y < 0.0 else 1.0
		velocity.y -= _gravity * gravity_scale * delta
	elif _intent.consume_jump() and not crouching and _try_traverse():
		return

	var speed: float = config["walk_speed"]
	var accel: float = config["acceleration"]
	if crouching:
		speed = config["crouch_speed"]
	elif _wants_sprint():
		speed = config["sprint_speed"]
		# Building up to a sprint takes a moment; slowing down stays snappy.
		if horizontal_speed() >= float(config["walk_speed"]) - 0.1:
			accel = config["sprint_acceleration"]
	if _intent.aim:
		speed *= float(config["ads_speed_multiplier"])
	if not is_on_floor():
		accel *= float(config["air_control"])
	var wish := transform.basis * Vector3(_intent.move.x, 0.0, -_intent.move.y)
	var target := wish.limit_length(1.0) * speed
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(Vector2(target.x, target.z), accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	move_and_slide()


## Space on the ground: vault low cover at speed, mantle ledges, otherwise a small hop.
## Returns true when a traversal started.
func _try_traverse() -> bool:
	if horizontal_speed() >= float(config["vault_min_speed"]):
		var vault: Variant = PlayerMantle.find_vault(self, config)
		if vault is Dictionary:
			var v: Dictionary = vault
			var top: Vector3 = v["top"]
			var landing: Vector3 = v["landing"]
			var over := global_position.lerp(landing, 0.5)
			over.y = top.y + float(config["vault_clearance"])
			# Carry the run through the vault.
			var flat := Vector3(velocity.x, 0.0, velocity.z)
			_start_path(Mode.VAULT, over, landing, flat)
			return true
	var ledge: Variant = PlayerMantle.find_ledge(self, config)
	if ledge is Vector3:
		var target: Vector3 = ledge
		var corner := Vector3(global_position.x, target.y + 0.1, global_position.z)
		_start_path(Mode.MANTLE, corner, target, Vector3.ZERO)
		return true
	velocity.y = config["jump_velocity"]
	return false


func _start_path(new_mode: Mode, over: Vector3, to: Vector3, exit_velocity: Vector3) -> void:
	mode = new_mode
	_path_t = 0.0
	_path_from = global_position
	_path_over = over
	_path_to = to
	_path_exit_velocity = exit_velocity
	velocity = Vector3.ZERO
	_apply_height(config["stand_height"])


## Quadratic curve through `_path_over`: rising first, then over the edge, so the body
## never clips the obstacle's corner. Vaults are quicker than mantles.
func _step_path(delta: float) -> void:
	var duration: float = config["vault_time"] if mode == Mode.VAULT else config["mantle_time"]
	_path_t = minf(_path_t + delta / duration, 1.0)
	var t := _path_t
	var a := _path_from.lerp(_path_over, t)
	var b := _path_over.lerp(_path_to, t)
	global_position = a.lerp(b, t)
	if _path_t >= 1.0:
		mode = Mode.NORMAL
		velocity = _path_exit_velocity


func _start_slide() -> void:
	mode = Mode.SLIDE
	_slide_left = config["slide_time"]
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var boosted := flat.normalized() * (flat.length() + float(config["slide_boost"]))
	velocity.x = boosted.x
	velocity.z = boosted.z
	_apply_height(config["crouch_height"])


func _step_slide(delta: float) -> void:
	_slide_left -= delta
	var flat := Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, float(config["slide_friction"]) * delta)
	velocity.x = flat.x
	velocity.z = flat.y
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()
	if _slide_left <= 0.0 or flat.length() <= float(config["crouch_speed"]) or not _intent.crouch:
		mode = Mode.NORMAL


## Resizes the capsule from the feet up, so crouching never pushes the body into the ground.
func _apply_height(height: float) -> void:
	if is_equal_approx(_capsule.height, height):
		return
	_capsule.height = height
	_capsule.radius = config["radius"]
	_shape_node.position.y = height / 2.0
	_head.position.y = height - float(config["eye_offset"])

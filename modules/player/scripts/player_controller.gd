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
	"wade_depth": TYPE_FLOAT,
	"wade_speed": TYPE_FLOAT,
	"swim_depth": TYPE_FLOAT,
	"swim_speed": TYPE_FLOAT,
	"step_height": TYPE_FLOAT,
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
	"lean_offset": TYPE_FLOAT,
	"lean_degrees": TYPE_FLOAT,
	"lean_seconds": TYPE_FLOAT,
	"eye_offset": TYPE_FLOAT,
	"radius": TYPE_FLOAT,
	"mouse_sensitivity": TYPE_FLOAT,
	"max_health": TYPE_FLOAT,
	"respawn_seconds": TYPE_FLOAT,
}
const PITCH_LIMIT := deg_to_rad(89.0)
## How far ahead a step is looked for, so a slow walk still finds the step before touching it.
const STEP_PROBE := 0.12
## How quickly a swimmer settles to floating height (per second, of the gap).
const SWIM_SETTLE := 4.0

enum Mode { NORMAL, MANTLE, VAULT, SLIDE }

@export var intent_path: NodePath
@export var head_path: NodePath
@export var shape_path: NodePath

var config: Dictionary = {}
var mode: Mode = Mode.NORMAL

var _intent: PlayerIntent
var _head: Node3D
## A leaning head keeps this far from walls.
const LEAN_CLEARANCE := 0.15
var _capsule: CapsuleShape3D
var _shape_node: CollisionShape3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _was_crouching := false
## -1 (full left) to 1 (full right), eased toward the intent's lean.
var _lean := 0.0
## Water deeper than `swim_depth` under the feet: floating, slow, weapon down.
var swimming := false
## The node answering `water_depth_at` (the voxel world), found once.
var _ground: Node

# Traversal (mantle and vault) runs along a scripted path instead of physics.
var _path_t := 0.0
var _path_from: Vector3
var _path_over: Vector3
var _path_to: Vector3
var _path_exit_velocity := Vector3.ZERO

var _slide_left := 0.0


## A copy of someone else's body on a client: it shows what the server sends and runs no
## movement of its own. Switched off once it is ready, because Godot switches physics on at
## `ready` for any script with `_physics_process`, undoing a switch-off made before.
static func hold_still(copy: PlayerController) -> void:
	copy.ready.connect(copy.set_physics_process.bind(false), CONNECT_ONE_SHOT)


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
	var prof := Prof.start()
	_physics_tick(delta)
	Prof.stop(&"player/player_controller:physics", prof)


func _physics_tick(delta: float) -> void:
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


## How far the player leans, -1 (left) to 1 (right). The body animator rolls the spine by it.
func lean_amount() -> float:
	return _lean


## Every instance, every frame: the head moves sideways and rolls with the lean, stopping
## short of walls so nobody peeks through one. On the server this moves the eye shots
## come from; clients ease toward the same synced lean.
func _process(delta: float) -> void:
	var prof := Prof.start()
	_process_tick(delta)
	Prof.stop(&"player/player_controller:frame", prof)


func _process_tick(delta: float) -> void:
	if _head == null or config.is_empty():
		return
	var want := float(_intent.lean) if mode == Mode.NORMAL and not is_sprinting() else 0.0
	_lean = move_toward(_lean, want, delta / maxf(float(config["lean_seconds"]), 0.01))
	var offset := _lean * float(config["lean_offset"])
	if absf(offset) > 0.01 and is_inside_tree():
		var from := global_transform * Vector3(0.0, _head.position.y, 0.0)
		var side := global_basis.x.normalized() * signf(offset)
		var query := PhysicsRayQueryParameters3D.create(from, from + side * (absf(offset) + LEAN_CLEARANCE), PhysicsLayers.SOLID, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			offset = signf(offset) * maxf(from.distance_to(hit["position"]) - LEAN_CLEARANCE, 0.0)
	_head.position.x = offset
	_head.rotation.z = -_lean * deg_to_rad(float(config["lean_degrees"]))


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

	var depth := water_depth()
	_set_swimming(depth > float(config["swim_depth"]))
	if swimming:
		# Afloat: held with the head out, the feet `swim_depth` under the surface.
		var surface := float(_ground.call(&"water_level_at", global_position))
		velocity.y = (surface - float(config["swim_depth"]) - global_position.y) * SWIM_SETTLE
		_intent.consume_jump()
	elif not is_on_floor():
		# Falling faster than rising makes jumps feel heavy instead of floaty.
		var gravity_scale: float = config["fall_gravity_multiplier"] if velocity.y < 0.0 else 1.0
		velocity.y -= _gravity * gravity_scale * delta
	elif _intent.consume_jump() and not crouching and _try_traverse():
		return

	var speed: float = config["walk_speed"]
	var accel: float = config["acceleration"]
	# Rate at which speed above what the body already has builds up; 0 builds at `accel`.
	var build := 0.0
	if crouching:
		speed = config["crouch_speed"]
	elif _wants_sprint():
		speed = config["sprint_speed"]
		# Building up to a sprint takes a moment; slowing down stays snappy.
		if horizontal_speed() >= float(config["walk_speed"]) - 0.1:
			build = config["sprint_acceleration"]
	if _intent.aim:
		speed *= float(config["ads_speed_multiplier"])
	if swimming:
		speed = float(config["walk_speed"]) * float(config["swim_speed"])
	elif depth > float(config["wade_depth"]):
		speed *= float(config["wade_speed"])
	if not is_on_floor() and not swimming:
		accel *= float(config["air_control"])
		build *= float(config["air_control"])
	var wish := transform.basis * Vector3(_intent.move.x, 0.0, -_intent.move.y)
	var target := wish.limit_length(1.0) * speed
	var goal := Vector2(target.x, target.z)
	var horizontal := Vector2(velocity.x, velocity.z)
	if build > 0.0 and goal.length() > 0.0:
		# Only gaining speed is slow: steering towards the new heading (up to the speed the body
		# has) runs at full `accel`, or a sprinting player slides sideways after every turn.
		var keep := goal.normalized() * minf(horizontal.length(), goal.length())
		horizontal = horizontal.move_toward(keep, accel * delta).move_toward(goal, build * delta)
	else:
		horizontal = horizontal.move_toward(goal, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	_move_with_steps(delta)


## `move_and_slide`, but a step no higher than `step_height` in the way (a stair, a kerb, a
## door sill) is walked up instead of stopping at: if the way ahead is blocked at the feet and
## free `step_height` higher, the body rises first and the floor snap sets it down on top.
func _move_with_steps(delta: float) -> void:
	var step := float(config["step_height"])
	var ahead := Vector3(velocity.x, 0.0, velocity.z) * delta
	var stepped := false
	if is_on_floor() and not swimming and ahead.length() > 0.0001:
		var probe := ahead.normalized() * maxf(ahead.length(), STEP_PROBE)
		if test_move(global_transform, probe):
			var up := Vector3.UP * step
			var raised := global_transform.translated(up)
			if not test_move(global_transform, up) and not test_move(raised, probe):
				global_position += up
				stepped = true
	var snap := floor_snap_length
	if stepped:
		floor_snap_length = step + 0.05
	move_and_slide()
	if stepped:
		apply_floor_snap()
		floor_snap_length = snap


## How deep the water is where the player stands (0 on land, or with no world that knows).
func water_depth() -> float:
	if _ground == null or not is_instance_valid(_ground):
		_ground = get_tree().get_first_node_in_group(&"ground") if is_inside_tree() else null
		if _ground == null or not _ground.has_method(&"water_depth_at"):
			_ground = null
			return 0.0
	return float(_ground.call(&"water_depth_at", global_position))


## Weapons read the meta (they hold no reference to this script's type).
func _set_swimming(on: bool) -> void:
	if on == swimming:
		return
	swimming = on
	set_meta(&"swimming", on)


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

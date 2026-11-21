class_name PlayerController
extends CharacterBody3D
## First-person movement driven only by PlayerIntent: walk, sprint with momentum, crouch,
## slide, hop, vault low cover, mantle onto ledges and climb ladders. Cosmetic camera feel
## (FOV, bob) lives in PlayerCameraFeel on clients; nothing here depends on rendering.

## A standing person, for checking where one can be put (#406): a little slimmer than the
## body so touching a car door does not count.
const STAND_CHECK_RADIUS := 0.3
const STAND_CHECK_HEIGHT := 1.7
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
	"climb_speed": TYPE_FLOAT,
	"climb_move_share": TYPE_FLOAT,
	"climb_aim": TYPE_FLOAT,
	"climb_top_margin": TYPE_FLOAT,
	"shove_fade": TYPE_FLOAT,
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
	"slide_cooldown_seconds": TYPE_FLOAT,
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
## Vertical speed (m/s) past which a copy held still counts as off the ground: the synced
## velocity jitters a little on slopes and steps.
const HELD_AIRBORNE_SPEED := 1.5

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
## Seconds until another slide may start: chained short slides, each starting fast, would
## otherwise outrun sprinting.
var _slide_cooldown := 0.0
## A push from outside (a car driving through, #409), on top of the body's own walking; it
## fades at player.json's `shove_fade` metres a second per second, whatever the body does.
var _shove := Vector3.ZERO
## The way into the ladder being climbed (level, unit).
var _ladder_into := Vector3.ZERO
## On a ladder, held to it with no gravity. Synced, so other screens show the climb instead
## of judging a body rising or sinking at climbing speed as falling.
var climbing := false


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
	return mode == Mode.NORMAL and _wants_sprint() and grounded() and horizontal_speed() > float(config["walk_speed"]) + 0.1


## On the ground: floor contact where this copy simulates; for one held still (someone else's
## copy on a client; on the server a held, parked or dead body) only its velocity says, so no
## climb or fall means grounded.
func grounded() -> bool:
	if is_physics_processing():
		return is_on_floor()
	return absf(velocity.y) <= HELD_AIRBORNE_SPEED


## Off the ground and not holding on to anything: what the body animator shows as falling.
func airborne() -> bool:
	return not climbing and not grounded()


## The way into the ladder being climbed (level, unit); zero when not climbing. A copy held
## still never steps, so it asks the ladders where it is.
func ladder_into() -> Vector3:
	if not climbing:
		return Vector3.ZERO
	if is_physics_processing():
		return _ladder_into
	var ladder := Ladders.at(global_position, _capsule.height, _capsule.radius)
	var into: Vector3 = ladder.get("into", Vector3.ZERO)
	return into


func _physics_process(delta: float) -> void:
	var prof := Prof.start()
	_physics_tick(delta)
	Prof.stop(&"player/player_controller:physics", prof)


func _physics_tick(delta: float) -> void:
	# Fades however the body moves this step (walking, sliding, vaulting), so none is left over.
	if _shove != Vector3.ZERO:
		_shove = _shove.move_toward(Vector3.ZERO, float(config["shove_fade"]) * delta)
	if _intent.consume_interact():
		# Whoever owns the thing in front of us (car, loot) decides what happens; `target` is
		# what this player's own screen offered, if anything.
		var aimed := _intent.consume_interact_target()
		var target := get_node_or_null(aimed) if not aimed.is_empty() else null
		EventBus.publish(&"player.interact", {"player": self, "target": target, "named": not aimed.is_empty()})
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
	if not is_physics_processing():
		# Held still (someone else's copy on a client; on the server a held or dead body), it
		# never steps, so its eye (where its gun aims from) follows crouch and slide here.
		_apply_height(config["crouch_height"] if _intent.crouch or mode == Mode.SLIDE else config["stand_height"])
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
	_slide_cooldown = maxf(_slide_cooldown - delta, 0.0)
	if crouch_pressed and _slide_cooldown <= 0.0 and is_on_floor() and _wants_sprint() and horizontal_speed() >= float(config["slide_min_speed"]):
		_start_slide()
		return
	_apply_height(config["crouch_height"] if crouching else config["stand_height"])

	var depth := water_depth()
	_set_swimming(depth > float(config["swim_depth"]))
	var ladder := {} if swimming else Ladders.at(global_position, _capsule.height, _capsule.radius)
	climbing = false
	if not ladder.is_empty():
		var into: Vector3 = ladder["into"]
		var aim := float(config["climb_aim"])
		var push := (transform.basis * Vector3(_intent.move.x, 0.0, -_intent.move.y)).limit_length(1.0).dot(into)
		var top := float(ladder["top"])
		# Onto it from the ground only heading into it and below its top (not from the deck it
		# leads to); off the ground beside it, holding on.
		climbing = not is_on_floor() or (push > aim and global_position.y < top - float(config["climb_top_margin"]))
		if climbing:
			# Into the ladder climbs, away from it climbs down, sideways holds on; never past its top.
			var up := float(config["climb_speed"]) * signf(push) if absf(push) > aim else 0.0
			velocity.y = minf(up, (top - global_position.y) / maxf(delta, 0.0001))
			_ladder_into = into
	if climbing:
		_intent.consume_jump()
	elif swimming:
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
	if climbing and not is_on_floor():
		speed *= float(config["climb_move_share"])
	elif not is_on_floor() and not swimming:
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
	if climbing and not is_on_floor():
		# Held to the ladder: pushing away from it climbs down rather than letting go.
		var away := -Vector3(velocity.x, 0.0, velocity.z).dot(_ladder_into)
		if away > 0.0:
			velocity += _ladder_into * away
	_move_with_steps(delta)
	_be_shoved(delta)


## Carried along by the push, apart from its own velocity so walking, sliding and swimming
## stay as they are; it slides along walls like any move.
func _be_shoved(delta: float) -> void:
	if _shove == Vector3.ZERO:
		return
	var step := Vector3(_shove.x, 0.0, _shove.z) * delta
	var hit := move_and_collide(step)
	if hit != null:
		move_and_collide(hit.get_remainder().slide(hit.get_normal()))


## Server: something pushes this body along `push` (metres a second): it is carried that way
## for a moment. The strongest push in a moment wins; they don't stack. The dead aren't.
func shove(push: Vector3) -> void:
	if get_meta(&"dead", false):
		return
	if push.length() > _shove.length():
		_shove = push


## Server: drops any push still carrying the body (it was stopped, moved or respawned).
func clear_shove() -> void:
	_shove = Vector3.ZERO


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
	climbing = false
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
	climbing = false
	_slide_left = config["slide_time"]
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	# The boost tops out one boost over sprint speed (repeated slides stacked it: 93 m/s in a
	# second and a half, and the server takes whatever intent it gets); faster than that
	# already, a slide keeps the speed it has rather than braking.
	var top := float(config["sprint_speed"]) + float(config["slide_boost"])
	var boosted := flat.normalized() * maxf(flat.length(), minf(flat.length() + float(config["slide_boost"]), top))
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
		_slide_cooldown = float(config["slide_cooldown_seconds"])


## Resizes the capsule from the feet up, so crouching never pushes the body into the ground.
func _apply_height(height: float) -> void:
	if is_equal_approx(_capsule.height, height):
		return
	_capsule.height = height
	_capsule.radius = config["radius"]
	_shape_node.position.y = height / 2.0
	_head.position.y = height - float(config["eye_offset"])


## Whether a vehicle's body overlaps a standing person with their feet at `at` in `world`.
static func vehicle_at(world: World3D, at: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = STAND_CHECK_RADIUS
	capsule.height = STAND_CHECK_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * (STAND_CHECK_HEIGHT / 2.0 + 0.05))
	query.collision_mask = PhysicsLayers.SOLID
	for hit: Dictionary in world.direct_space_state.intersect_shape(query, 8):
		var body := hit.get("collider") as Node
		if body != null and body.is_in_group(&"vehicles"):
			return true
	return false

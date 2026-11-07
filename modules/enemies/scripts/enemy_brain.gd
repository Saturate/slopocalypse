class_name EnemyBrain
extends Node
## Server only: drives one enemy soldier through the same intent a player's keyboard
## fills, so it moves, aims and shoots with the real body and gun. It patrols around its
## home, spots players it can see (range, cone, line of sight) or hears shooting, turns to
## them, and fires bursts once it has had time to react; its aim tightens the longer it
## watches. Lost targets are chased to where they were last seen, then forgotten.

enum State { PATROL, FIGHT, CHASE }

## How high on a player to aim and to check sight against: the chest.
const CHEST := 1.3
## Close enough to a patrol point to count as there.
const ARRIVED := 1.5
## Fire only when the aim is within this of the target, radians.
const ON_TARGET := 0.12

var body: PlayerController
var config: Dictionary = {}
var home := Vector3.ZERO

var state := State.PATROL
var target: Node3D
var last_seen := Vector3.ZERO

var _rng := RandomNumberGenerator.new()
var _yaw := 0.0
var _pitch := 0.0
var _seen_for := 0.0
var _lost_for := 0.0
var _goal := Vector3.ZERO
var _pause := 0.0
var _burst_left := 0.0
var _burst_pause := 0.0
var _error := Vector2.ZERO


func _ready() -> void:
	_rng.randomize()
	_yaw = body.rotation.y
	_goal = home
	EventBus.subscribe(&"weapon.fired", _on_shot_heard)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"weapon.fired", _on_shot_heard)


## The yaw and pitch that look from `from` toward `to` (yaw about +Y with -Z forward,
## pitch positive up), as the player's body and head use them.
static func look_angles(from: Vector3, to: Vector3) -> Vector2:
	var d := to - from
	var flat := Vector2(d.x, d.z).length()
	return Vector2(atan2(-d.x, -d.z), atan2(d.y, flat))


## Whether a point at `to` is inside a cone of `cone_degrees` around `facing_yaw`.
static func in_cone(from: Vector3, facing_yaw: float, to: Vector3, cone_degrees: float) -> bool:
	var want := look_angles(from, to).x
	return absf(angle_difference(facing_yaw, want)) <= deg_to_rad(cone_degrees) / 2.0


## Aim error for how long the target has been watched: wide at first, settling down.
static func aim_error(seen_for: float, widest: float, tightest: float, settle_seconds: float) -> float:
	return lerpf(widest, tightest, clampf(seen_for / maxf(settle_seconds, 0.01), 0.0, 1.0))


func _physics_process(delta: float) -> void:
	var intent := body.intent()
	if body.get_meta(&"dead", false):
		intent.move = Vector2.ZERO
		intent.fire = false
		return
	var seen := _find_target()
	if seen != null:
		if target != seen:
			_seen_for = 0.0
		target = seen
		last_seen = seen.global_position
		_lost_for = 0.0
		_seen_for += delta
		state = State.FIGHT
	elif target != null:
		_seen_for = 0.0
		_lost_for += delta
		if _lost_for > float(config["forget_seconds"]) or not is_instance_valid(target):
			target = null
			state = State.PATROL
			_goal = _patrol_point()
		elif _lost_for > float(config["chase_seconds"]):
			state = State.PATROL
		else:
			state = State.CHASE
	intent.fire = false
	intent.aim = false
	match state:
		State.PATROL:
			_patrol(delta, intent)
		State.CHASE:
			_walk_toward(last_seen, delta, intent, 1.0)
		State.FIGHT:
			_fight(delta, intent)
	intent.look_yaw = _yaw
	intent.look_pitch = _pitch
	intent.remote_look = true


func _patrol(delta: float, intent: PlayerIntent) -> void:
	if _pause > 0.0:
		_pause -= delta
		intent.move = Vector2.ZERO
		return
	var flat := Vector2(_goal.x - body.global_position.x, _goal.z - body.global_position.z)
	if flat.length() < ARRIVED:
		var pause: Array = config["patrol_pause_seconds"]
		_pause = _rng.randf_range(float(pause[0]), float(pause[1]))
		_goal = _patrol_point()
		intent.move = Vector2.ZERO
		return
	_walk_toward(_goal, delta, intent, float(config["walk_speed_share"]))


func _walk_toward(at: Vector3, delta: float, intent: PlayerIntent, speed: float) -> void:
	var want := look_angles(body.global_position, at).x
	_turn_to(want, 0.0, delta)
	var flat := Vector2(at.x - body.global_position.x, at.z - body.global_position.z)
	intent.move = Vector2(0.0, speed) if flat.length() > ARRIVED else Vector2.ZERO


func _fight(delta: float, intent: PlayerIntent) -> void:
	intent.move = Vector2.ZERO
	intent.aim = true
	var eye := _eye()
	var want := look_angles(eye, target.global_position + Vector3.UP * CHEST)
	var errors: Array = config["aim_error_degrees"]
	var spread := deg_to_rad(aim_error(_seen_for, float(errors[0]), float(errors[1]), float(config["aim_settle_seconds"])))
	_turn_to(want.x + _error.x * spread, want.y + _error.y * spread, delta)
	if _seen_for < float(config["reaction_seconds"]):
		return
	var on_target := absf(angle_difference(_yaw, want.x)) < ON_TARGET + spread and absf(_pitch - want.y) < ON_TARGET + spread
	if _burst_pause > 0.0:
		_burst_pause -= delta
		return
	if _burst_left <= 0.0:
		var shots: Array = config["burst_shots"]
		# Seconds of trigger; the gun's own fire rate turns it into shots.
		_burst_left = float(_rng.randi_range(int(shots[0]), int(shots[1]))) * 0.1
		_error = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
	if on_target:
		intent.fire = true
		_burst_left -= delta
		if _burst_left <= 0.0:
			var pauses: Array = config["burst_pause_seconds"]
			_burst_pause = _rng.randf_range(float(pauses[0]), float(pauses[1]))


func _turn_to(yaw: float, pitch: float, delta: float) -> void:
	var step := float(config["turn_speed"]) * delta
	_yaw += clampf(angle_difference(_yaw, yaw), -step, step)
	_pitch = move_toward(_pitch, clampf(pitch, -1.2, 1.2), step)


## The nearest living player this soldier can see, or null.
func _find_target() -> Node3D:
	var eye := _eye()
	var best: Node3D = null
	var best_d := float(config["sight_range"])
	var cone := float(config["sight_cone_degrees"])
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Node3D
		if player == null or player.get_meta(&"dead", false) or not player.is_visible_in_tree():
			continue
		var chest := player.global_position + Vector3.UP * CHEST
		var d := eye.distance_to(chest)
		if d > best_d:
			continue
		# Something already being fought is tracked all round, not only ahead.
		if player != target and not in_cone(eye, _yaw, chest, cone):
			continue
		if _clear_line(eye, chest, player):
			best = player
			best_d = d
	return best


func _clear_line(from: Vector3, to: Vector3, wanted: Node) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider: Variant = hit["collider"]
	return collider is Node and (collider == wanted or (wanted as Node).is_ancestor_of(collider as Node))


## Gunfire nearby draws attention to the shooter, even out of sight.
func _on_shot_heard(p: Dictionary) -> void:
	var shooter := p.get("holder") as Node3D
	if shooter == null or not shooter.is_in_group(&"players") or body.get_meta(&"dead", false):
		return
	if body.global_position.distance_to(shooter.global_position) > float(config["hearing_range"]):
		return
	if target == null or state == State.PATROL:
		target = shooter
		last_seen = shooter.global_position
		_lost_for = 0.0
		state = State.CHASE


func _eye() -> Vector3:
	var camera := body.get_node_or_null("Head/Camera") as Node3D
	return camera.global_position if camera != null else body.global_position + Vector3.UP * 1.6


func _patrol_point() -> Vector3:
	var r := float(config["patrol_radius"])
	var a := _rng.randf() * TAU
	return home + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(r * 0.3, r)

class_name CivilianBrain
extends Node
## Server: an unarmed civilian (#342). Calm, they stroll between spots near home (their
## building's door) and stop now and then. Gunfire or a blast within `hearing_range` alarms
## them: most run to the nearest refuge away from the noise (a building door) and crouch
## there; some freeze and crouch where they stand. After `calm_seconds` of quiet they go back
## to strolling. They never carry or pick up anything and never attack.

enum State { CALM, FLEE, HIDE }

const ARRIVED := 0.8

var body: PlayerController
## enemies.json's `civilians` block.
var config: Dictionary = {}
var home := Vector3.ZERO
## Where to run when alarmed: building doors, world positions.
var refuges: Array[Vector3] = []
var state := State.CALM

var _goal := Vector3.ZERO
var _pause := 0.0
var _quiet := 0.0
var _yaw := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_yaw = body.rotation.y
	_goal = _stroll_spot()
	EventBus.subscribe(&"weapon.fired", _on_shot)
	EventBus.subscribe(&"explosion", _on_explosion)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"weapon.fired", _on_shot)
	EventBus.unsubscribe(&"explosion", _on_explosion)


func _physics_process(delta: float) -> void:
	var prof := Prof.start()
	_physics_tick(delta)
	Prof.stop(&"enemies/civilian_brain:physics", prof)


func _physics_tick(delta: float) -> void:
	var intent := body.intent()
	if body.get_meta(&"dead", false):
		intent.move = Vector2.ZERO
		return
	match state:
		State.CALM:
			intent.crouch = false
			intent.sprint = false
			if _pause > 0.0:
				_pause -= delta
				intent.move = Vector2.ZERO
			elif _walk_to(_goal, intent, float(config.get("walk_share", 0.5))):
				var pauses: Array = config.get("pause_seconds", [2.0, 6.0])
				_pause = _rng.randf_range(float(pauses[0]), float(pauses[1]))
				_goal = _stroll_spot()
		State.FLEE:
			intent.sprint = true
			if _walk_to(_goal, intent, 1.0):
				state = State.HIDE
		State.HIDE:
			intent.move = Vector2.ZERO
			intent.sprint = false
			intent.crouch = true
			_quiet += delta
			if _quiet >= float(config.get("calm_seconds", 90.0)):
				state = State.CALM
				_goal = _stroll_spot()
	intent.look_yaw = _yaw
	intent.look_pitch = 0.0
	intent.remote_look = true


## Heads for `at`; true once there.
func _walk_to(at: Vector3, intent: PlayerIntent, speed: float) -> bool:
	var flat := Vector2(at.x - body.global_position.x, at.z - body.global_position.z)
	if flat.length() <= ARRIVED:
		intent.move = Vector2.ZERO
		return true
	_yaw = EnemyBrain.look_angles(body.global_position, at).x
	# Facing the way it walks: straight ahead.
	intent.move = Vector2(0.0, speed)
	return false


func _stroll_spot() -> Vector3:
	var r := float(config.get("stroll_radius", 8.0))
	var a := _rng.randf() * TAU
	return home + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(r * 0.3, r)


## Alarmed (running or hiding): it stays awake far from players (BrainSleep).
func busy() -> bool:
	return state != State.CALM


## Something loud happened at `at`.
func alarm(at: Vector3) -> void:
	if body.get_meta(&"dead", false):
		return
	if body.global_position.distance_to(at) > float(config.get("hearing_range", 60.0)):
		return
	_quiet = 0.0
	if not is_physics_processing():
		BrainSleep.wake(body)
	if state != State.CALM:
		return
	if refuges.is_empty() or _rng.randf() < float(config.get("freeze_share", 0.25)):
		state = State.HIDE
		return
	_goal = refuge_from(at)
	state = State.FLEE


## The nearest refuge on the far side from the noise; the nearest of all if none is.
func refuge_from(noise: Vector3) -> Vector3:
	var here := body.global_position
	var away := (here - noise)
	away.y = 0.0
	var best := refuges[0]
	var best_d := INF
	var best_away := Vector3.ZERO
	var best_away_d := INF
	for r: Vector3 in refuges:
		var d := here.distance_to(r)
		if d < best_d:
			best_d = d
			best = r
		if away.dot(r - here) > 0.0 and d < best_away_d:
			best_away_d = d
			best_away = r
	return best_away if best_away_d < INF else best


func _on_shot(p: Dictionary) -> void:
	if p.has("from"):
		alarm(p["from"] as Vector3)
	if p.has("to"):
		alarm(p["to"] as Vector3)


func _on_explosion(p: Dictionary) -> void:
	if p.has("position"):
		alarm(p["position"] as Vector3)

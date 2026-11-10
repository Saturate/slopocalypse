class_name EnemyBrain
extends Node
## Server only: drives one enemy soldier through the same intent a player's keyboard
## fills, so it moves, aims and shoots with the real body and gun. It patrols around its
## home, spots players it can see (range, cone, line of sight) or hears shooting, turns to
## them, and fires bursts once it has had time to react; its aim tightens the longer it
## watches. Lost targets are chased to where they were last seen, then forgotten. A guard
## (`has_post`) does not wander: it holds its post, slowly scanning either side of
## `post_yaw`, or walks its `route` round and round, and goes back there after a fight.
##
## Under fire it is a person, not a turret (`Fortitude`): bullets passing close and blasts
## nearby build suppression, which pins it (it ducks and its aim goes wide); while fighting
## its fortitude band decides whether it fights (chases, fires freely), postures (holds its
## ground and fires when it has a shot), flees (runs from the threat, firing only when
## cornered) or submits (drops its gun and stays down for good). It never fires unless a
## ray from its muzzle to the target is clear of walls and leaves.
##
## In a fight it uses cover: it looks for a spot near it that hides it (crouched) from the
## threat, preferably one it can stand up from to fire, runs there (one squad mate at a time
## while the others keep firing), then hides and peeks in turns; pinned, it stays down. A
## soldier who spots someone calls it out to squad mates within earshot.

enum State { PATROL, FIGHT, CHASE }

## How high on a player to aim and to check sight against: the chest.
const CHEST := 1.3
## Close enough to a patrol point to count as there.
const ARRIVED := 1.5
## Fire only when the aim is within this of the target, radians.
const ON_TARGET := 0.12
## Where a body counts as hidden from a threat: something solid in front of the waist.
const WAIST := 0.9
## The muzzle sits about this far in front of the eye.
const MUZZLE_AHEAD := 0.6

var body: PlayerController
var config: Dictionary = {}
var home := Vector3.ZERO

## A guard's post and route (see the class comment).
var has_post := false
var post_yaw := 0.0
var route: Array[Vector3] = []

## Fear: the fixed starting fortitude, the band it is in now, and suppression (pinned above
## the config's threshold).
var fortitude_start := 20
var mood := Fortitude.FIGHT
var suppression := 0.0
var surrendered := false

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
var _route_index := 0
var _scan_time := 0.0
var _evaluate_in := 0.0
## Cover: the spot it uses (valid while `_has_cover`), when it looks again, and the peek cycle.
var _has_cover := false
var _cover := Vector3.ZERO
var _cover_search_in := 0.0
var _peeking := false
var _peek_left := 0.0


func _ready() -> void:
	_rng.randomize()
	fortitude_start = Fortitude.roll(_fear(), _rng)
	_yaw = body.rotation.y
	_goal = route[0] if not route.is_empty() else home
	EventBus.subscribe(&"weapon.fired", _on_shot_heard)
	EventBus.subscribe(&"explosion", _on_explosion)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"weapon.fired", _on_shot_heard)
	EventBus.unsubscribe(&"explosion", _on_explosion)


func _fear() -> Dictionary:
	return config.get("fortitude", {})


func _suppression_cfg() -> Dictionary:
	return config.get("suppression", {})


func is_pinned() -> bool:
	return suppression >= float(_suppression_cfg().get("pinned", 1.0))


## Closest distance from `point` to the segment `a`..`b`.
static func distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return point.distance_to(a + ab * t)


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
	var prof := Prof.start()
	_physics_tick(delta)
	Prof.stop(&"enemies/enemy_brain:physics", prof)


func _physics_tick(delta: float) -> void:
	var intent := body.intent()
	if body.get_meta(&"dead", false):
		intent.move = Vector2.ZERO
		intent.fire = false
		return
	suppression = maxf(suppression - float(_suppression_cfg().get("decay", 0.35)) * delta, 0.0)
	if surrendered:
		intent.move = Vector2.ZERO
		intent.fire = false
		intent.aim = false
		intent.crouch = true
		return
	var seen := _find_target()
	if seen != null:
		if target != seen:
			_seen_for = 0.0
			_call_out(seen)
		target = seen
		last_seen = seen.global_position
		_lost_for = 0.0
		_seen_for += delta
		state = State.FIGHT
	elif target != null:
		# Ducking out of sight behind cover should not cost the whole aim: it fades.
		_seen_for = maxf(_seen_for - delta * 2.0, 0.0)
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
	intent.sprint = false
	_evaluate_fear(delta)
	if surrendered:
		return
	intent.crouch = is_pinned()
	if state == State.PATROL or target == null:
		_drop_cover()
	if state != State.PATROL and mood == Fortitude.FLEE:
		_drop_cover()
		_flee(delta, intent)
	elif state != State.PATROL and target != null and _use_cover(delta, intent):
		pass
	else:
		match state:
			State.PATROL:
				_patrol(delta, intent)
			State.CHASE:
				# Only a soldier with fight in it goes looking; the rest hold.
				if mood == Fortitude.FIGHT:
					_walk_toward(last_seen, delta, intent, 1.0)
				else:
					intent.move = Vector2.ZERO
			State.FIGHT:
				_fight(delta, intent)
	intent.look_yaw = _yaw
	intent.look_pitch = _pitch
	intent.remote_look = true


func _patrol(delta: float, intent: PlayerIntent) -> void:
	if has_post and route.is_empty():
		_hold_post(delta, intent)
		return
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


## Back to the post if pushed off it, then stand and look either side of the post's facing.
func _hold_post(delta: float, intent: PlayerIntent) -> void:
	var flat := Vector2(home.x - body.global_position.x, home.z - body.global_position.z)
	if flat.length() > ARRIVED:
		_walk_toward(home, delta, intent, float(config["walk_speed_share"]))
		return
	intent.move = Vector2.ZERO
	_scan_time += delta
	var sweep := deg_to_rad(float(config.get("post_scan_degrees", 60.0))) / 2.0
	var period := maxf(float(config.get("post_scan_seconds", 8.0)), 0.1)
	_turn_to(post_yaw + sin(_scan_time / period * TAU) * sweep, 0.0, delta)


## Turns towards `at` and moves straight at it whatever way it faces yet (forward plus a
## sidestep), so it never circles a spot it is turning too slowly to face.
func _walk_toward(at: Vector3, delta: float, intent: PlayerIntent, speed: float) -> void:
	var want := look_angles(body.global_position, at).x
	_turn_to(want, 0.0, delta)
	var flat := Vector2(at.x - body.global_position.x, at.z - body.global_position.z)
	if flat.length() <= ARRIVED * 0.5:
		intent.move = Vector2.ZERO
		return
	var dir := flat.normalized()
	var forward := Vector2(-sin(_yaw), -cos(_yaw))
	var right := Vector2(cos(_yaw), -sin(_yaw))
	intent.move = Vector2(dir.dot(right), dir.dot(forward)) * speed


func _fight(delta: float, intent: PlayerIntent) -> void:
	intent.move = Vector2.ZERO
	intent.aim = true
	var eye := _eye()
	var want := look_angles(eye, target.global_position + Vector3.UP * CHEST)
	var errors: Array = config["aim_error_degrees"]
	var spread := deg_to_rad(aim_error(_seen_for, float(errors[0]), float(errors[1]), float(config["aim_settle_seconds"])))
	if is_pinned():
		spread *= float(_suppression_cfg().get("pinned_aim_scale", 2.5))
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
	if on_target and clear_shot(target):
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
	# Sight stops at anything solid and at leaves: no shooting at someone hidden in a tree.
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.SOLID | PhysicsLayers.SIGHT)
	query.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider: Variant = hit["collider"]
	return collider is Node and (collider == wanted or (wanted as Node).is_ancestor_of(collider as Node))


## Gunfire nearby draws attention to the shooter, even out of sight; bullets passing close
## (or hitting it) build suppression.
func _on_shot_heard(p: Dictionary) -> void:
	var shooter := p.get("holder") as Node3D
	if shooter == null or not shooter.is_in_group(&"players") or body.get_meta(&"dead", false):
		return
	var sup := _suppression_cfg()
	var chest := body.global_position + Vector3.UP * CHEST
	if p.has("from") and p.has("to") and distance_to_segment(chest, p["from"], p["to"]) < float(sup.get("near_miss", 2.0)):
		suppression += float(sup.get("per_shot", 0.25))
		if target == null:
			target = shooter
			last_seen = shooter.global_position
			state = State.CHASE
	if body.global_position.distance_to(shooter.global_position) > float(config["hearing_range"]):
		return
	if target == null or state == State.PATROL:
		target = shooter
		last_seen = shooter.global_position
		_lost_for = 0.0
		state = State.CHASE


## Blasts nearby build suppression: a lot close in, less further out.
func _on_explosion(p: Dictionary) -> void:
	if body.get_meta(&"dead", false) or not p.has("position"):
		return
	var reach := float(p.get("radius", 2.0)) * float(_suppression_cfg().get("explosion_reach", 4.0))
	var d := body.global_position.distance_to(p["position"])
	if d < reach:
		suppression += float(_suppression_cfg().get("explosion", 1.5)) * (1.0 - d / reach)


## Whether a shot from the muzzle would reach `who`: nothing solid and no leaves on the way.
func clear_shot(who: Node3D) -> bool:
	return _clear_line(_muzzle(), who.global_position + Vector3.UP * CHEST, who)


## Roughly where the barrel ends: a little in front of the eye along the look.
func _muzzle() -> Vector3:
	var camera := body.get_node_or_null("Head/Camera") as Node3D
	if camera == null:
		return _eye()
	return camera.global_position - camera.global_basis.z * MUZZLE_AHEAD


## Every `evaluate_seconds` while it has a target: works out the fortitude band from what is
## happening. Submitting is for good.
func _evaluate_fear(delta: float) -> void:
	if target == null:
		mood = Fortitude.FIGHT
		return
	_evaluate_in -= delta
	if _evaluate_in > 0.0:
		return
	_evaluate_in = float(_fear().get("evaluate_seconds", 0.5))
	var health := body.get_node_or_null("Health") as HealthComponent
	var situation := {
		"ally_in_sight": _ally_in_sight(),
		"pinned": is_pinned(),
		"in_cover": _in_cover(),
		"wounded": health != null and health.health < health.max_health * float(_fear().get("wounded_share", 0.6)),
	}
	mood = Fortitude.band(_fear(), Fortitude.total(_fear(), fortitude_start, situation))
	if mood == Fortitude.SUBMIT:
		server_surrender()


## Server: gives up for good: drops its gun and stays down.
func server_surrender() -> void:
	if surrendered:
		return
	surrendered = true
	mood = Fortitude.SUBMIT
	var intent := body.intent()
	intent.fire = false
	intent.move = Vector2.ZERO
	Net.server_broadcast(&"enemy.surrendered", {"enemy": body})


func _ally_in_sight() -> bool:
	var eye := _eye()
	var reach := float(_fear().get("ally_range", 25.0))
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var ally := node as Node3D
		if ally == null or ally == body or ally.get_meta(&"dead", false) or ally.get_meta(&"surrendered", false):
			continue
		var chest := ally.global_position + Vector3.UP * CHEST
		if eye.distance_to(chest) < reach and _clear_line(eye, chest, ally):
			return true
	return false


## Something solid between the threat and its waist: it is behind cover.
func _in_cover() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var from := target.global_position + Vector3.UP * 1.5
	var to := body.global_position + Vector3.UP * WAIST
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.SOLID)
	var skip: Array[RID] = [body.get_rid()]
	if target is CollisionObject3D:
		skip.append((target as CollisionObject3D).get_rid())
	query.exclude = skip
	return not body.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Runs from the threat at full speed; fires back only when cornered (the threat close and
## in sight).
func _flee(delta: float, intent: PlayerIntent) -> void:
	var threat := last_seen if target == null or not is_instance_valid(target) else target.global_position
	var away := body.global_position - threat
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.FORWARD
	if state == State.FIGHT and target != null and body.global_position.distance_to(target.global_position) < float(_fear().get("cornered_range", 8.0)):
		_fight(delta, intent)
		return
	_walk_toward(body.global_position + away.normalized() * 10.0, delta, intent, 1.0)
	intent.sprint = true


func _cover_cfg() -> Dictionary:
	return config.get("cover", {})


func has_cover() -> bool:
	return _has_cover


func cover_spot() -> Vector3:
	return _cover


## Runs to cover and fights from it. False when there is no cover to use (it fights where it
## stands instead).
func _use_cover(delta: float, intent: PlayerIntent) -> bool:
	var threat := last_seen
	_cover_search_in -= delta
	if _cover_search_in <= 0.0 and (not _has_cover or not hidden_at(_cover, threat)):
		_cover_search_in = float(_cover_cfg().get("search_every", 1.5))
		var found: Variant = find_cover(threat)
		_has_cover = found is Vector3
		if _has_cover:
			_cover = found
	if not _has_cover:
		return false
	var flat := Vector2(_cover.x - body.global_position.x, _cover.z - body.global_position.z)
	if flat.length() > ARRIVED * 0.6:
		# One at a time: wait (and keep firing) while a squad mate close by is on the move.
		if not is_pinned() and _mate_moving():
			body.set_meta(&"moving_to_cover", false)
			return false
		body.set_meta(&"moving_to_cover", true)
		_walk_toward(_cover, delta, intent, 1.0)
		intent.sprint = true
		return true
	body.set_meta(&"moving_to_cover", false)
	intent.move = Vector2.ZERO
	_peek_left -= delta
	if _peek_left <= 0.0:
		_peeking = not _peeking
		var r: Array = _cover_cfg().get("peek_seconds" if _peeking else "hide_seconds", [1.5, 2.0])
		_peek_left = _rng.randf_range(float(r[0]), float(r[1]))
	if is_pinned() or not _peeking:
		intent.crouch = true
		var want := look_angles(_eye(), threat + Vector3.UP * CHEST)
		_turn_to(want.x, want.y, delta)
		return true
	intent.crouch = false
	if state == State.FIGHT:
		_fight(delta, intent)
	else:
		var want := look_angles(_eye(), threat + Vector3.UP * CHEST)
		_turn_to(want.x, want.y, delta)
		intent.aim = true
	return true


func _drop_cover() -> void:
	_has_cover = false
	_peeking = false
	if body.get_meta(&"moving_to_cover", false):
		body.set_meta(&"moving_to_cover", false)


func _mate_moving() -> bool:
	var reach := float(_cover_cfg().get("bound_range", 15.0))
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var mate := node as Node3D
		if mate != null and mate != body and mate.get_meta(&"moving_to_cover", false) and not mate.get_meta(&"dead", false) and mate.global_position.distance_to(body.global_position) < reach:
			return true
	return false


## Whether a body crouched at `spot` is hidden from someone standing at `threat`.
func hidden_at(spot: Vector3, threat: Vector3) -> bool:
	var from := threat + Vector3.UP * float(_cover_cfg().get("threat_eye", 1.5))
	var to := spot + Vector3.UP * float(_cover_cfg().get("crouch_height", 0.9))
	return _blocked(from, to, PhysicsLayers.SOLID)


## The best spot near it that hides it from `threat` (preferring ones it can stand up from to
## fire, and short runs), or null.
func find_cover(threat: Vector3) -> Variant:
	var cfg := _cover_cfg()
	var reach := float(cfg.get("search_radius", 12.0))
	var rings := int(cfg.get("rings", 4))
	var spokes := int(cfg.get("spokes", 12))
	var keep_off := float(cfg.get("min_threat_distance", 5.0))
	var stand := float(cfg.get("stand_eye", 1.5))
	var best: Variant = null
	var best_score := INF
	var candidates: Array[Vector3] = [body.global_position]
	for ring in rings:
		var r := reach * float(ring + 1) / rings
		for i in spokes:
			var a := TAU * (float(i) + 0.5 * (ring % 2)) / spokes
			candidates.append(body.global_position + Vector3(cos(a), 0.0, sin(a)) * r)
	for c in candidates:
		var spot: Variant = _floor_at(c)
		if not spot is Vector3:
			continue
		var at: Vector3 = spot
		if Vector2(at.x - threat.x, at.z - threat.z).length() < keep_off or not hidden_at(at, threat):
			continue
		var can_fire := not _blocked(at + Vector3.UP * stand, threat + Vector3.UP * CHEST, PhysicsLayers.SOLID | PhysicsLayers.SIGHT)
		var score := at.distance_to(body.global_position) + (0.0 if can_fire else float(cfg.get("no_shot_penalty", 8.0)))
		if score < best_score:
			best_score = score
			best = at
	return best


## The floor under `at` (a ray down from a little above), or null where there is none.
func _floor_at(at: Vector3) -> Variant:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 6.0, PhysicsLayers.SOLID)
	query.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit["position"]


func _blocked(from: Vector3, to: Vector3, mask: int) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	var skip: Array[RID] = [body.get_rid()]
	if target is CollisionObject3D and is_instance_valid(target):
		skip.append((target as CollisionObject3D).get_rid())
	query.exclude = skip
	return not body.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Tells squad mates within earshot where the one it just spotted is.
func _call_out(who: Node3D) -> void:
	var reach := float(_cover_cfg().get("callout_range", 30.0))
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		if node == body or node.get_meta(&"dead", false) or (node as Node3D).global_position.distance_to(body.global_position) > reach:
			continue
		var brain := node.get_node_or_null("Brain") as EnemyBrain
		if brain != null:
			brain.hear_callout(who)


## A squad mate called out `who`: go after them if it has nothing to fight yet.
func hear_callout(who: Node3D) -> void:
	if surrendered or body.get_meta(&"dead", false) or target != null:
		return
	target = who
	last_seen = who.global_position
	_lost_for = 0.0
	state = State.CHASE


func _eye() -> Vector3:
	var camera := body.get_node_or_null("Head/Camera") as Node3D
	return camera.global_position if camera != null else body.global_position + Vector3.UP * 1.6


func _patrol_point() -> Vector3:
	if not route.is_empty():
		_route_index = (_route_index + 1) % route.size()
		return route[_route_index]
	if has_post:
		return home
	var r := float(config["patrol_radius"])
	var a := _rng.randf() * TAU
	return home + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(r * 0.3, r)

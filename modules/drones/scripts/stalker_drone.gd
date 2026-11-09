class_name StalkerDrone
extends CharacterBody3D
## A drone that stalks a target. Calm, it circles wide and high and leaves you alone. Shot
## at, or held in someone's sights, it turns angry: it closes to its attack orbit, picks
## the one who provoked it, and every so often dives at them and blows up on contact (a
## whine warns everyone first). Left alone for a while it calms down again. Shot down, it
## tumbles out of the sky and its crash hurts whatever is near. All decisions run on the
## server; rotor spin, the light and the hum are cosmetic.

signal destroyed

const CONFIG := "res://modules/drones/data/drones.json"
const REQUIRED := {
	"max_health": TYPE_FLOAT, "speed": TYPE_FLOAT, "acceleration": TYPE_FLOAT,
	"orbit_radius": TYPE_FLOAT, "orbit_height": TYPE_FLOAT, "orbit_speed": TYPE_FLOAT,
	"min_ground_clearance": TYPE_FLOAT, "direction_change_seconds": TYPE_FLOAT,
	"fall_seconds": TYPE_FLOAT, "crash_radius": TYPE_FLOAT, "crash_damage": TYPE_FLOAT,
	"dive_interval_seconds": TYPE_ARRAY, "dive_speed": TYPE_FLOAT, "dive_seconds": TYPE_FLOAT,
	"dive_trigger_radius": TYPE_FLOAT, "dive_blast_radius": TYPE_FLOAT, "dive_damage": TYPE_FLOAT,
	"calm_orbit_radius": TYPE_FLOAT, "calm_orbit_height": TYPE_FLOAT, "aim_cone_degrees": TYPE_FLOAT,
	"aim_range": TYPE_FLOAT, "aim_seconds": TYPE_FLOAT, "calm_after_seconds": TYPE_FLOAT,
}

@export var health_path: NodePath
@export var rotors_path: NodePath
@export var light_path: NodePath

var config: Dictionary = {}
var target: Node3D
var downed := false

var _health: HealthComponent
var _rotors: Node3D
var _light: OmniLight3D
var _orbit_angle := 0.0
var _orbit_direction := 1.0
var _until_turn := 0.0
var _fall_left := 0.0
var _tumble := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _until_dive := 0.0
var _dive_left := -1.0
var _angry := false
## Seconds someone has held it in their sights, and since anyone last provoked it.
var _aimed_for := 0.0
var _calm_in := 0.0


func _ready() -> void:
	_health = get_node(health_path)
	_rotors = get_node(rotors_path)
	_light = get_node(light_path)
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not Data.require(CONFIG, data, REQUIRED):
		set_physics_process(false)
		return
	config = data
	_rng.seed = get_instance_id()
	_orbit_angle = _rng.randf() * TAU
	_until_turn = config["direction_change_seconds"]
	_until_dive = _next_dive()
	_health.died.connect(_on_died)
	_health.damaged.connect(_on_damaged)
	# Local only: tells this machine's audio a drone exists, so it can give it a hum.
	EventBus.publish(&"drone.spawned", {"drone": self})


func health() -> HealthComponent:
	return _health


func _process(delta: float) -> void:
	var prof := Prof.start()
	_process_tick(delta)
	Prof.stop(&"drones/stalker_drone:frame", prof)


func _process_tick(delta: float) -> void:
	# Cosmetic: rotors spin (slower once downed), light blinks.
	var spin := 40.0 if not downed else 8.0
	for rotor in _rotors.get_children():
		(rotor as Node3D).rotate_y(spin * delta)
	_light.light_energy = 2.5 if fmod(Time.get_ticks_msec() / 1000.0, 0.8) < 0.15 else 0.0


func _physics_process(delta: float) -> void:
	var prof := Prof.start()
	_physics_tick(delta)
	Prof.stop(&"drones/stalker_drone:physics", prof)


func _physics_tick(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if downed:
		_step_fall(delta)
	else:
		_step_stalk(delta)


func is_angry() -> bool:
	return _angry


## Server: someone provoked it (shot it, or held it in their sights). It goes after them.
func server_anger(provoker: Node3D) -> void:
	_calm_in = float(config["calm_after_seconds"])
	if provoker != null:
		target = provoker
	if _angry:
		return
	_angry = true
	_until_dive = _next_dive()
	Net.server_broadcast(&"drone.mood", {"drone": self, "angry": true})


func _calm_down() -> void:
	_angry = false
	_dive_left = -1.0
	Net.server_broadcast(&"drone.mood", {"drone": self, "angry": false})


func _on_damaged(_amount: float, source: Node) -> void:
	if downed or not multiplayer.is_server():
		return
	# The weapon's holder is the one to blame; anything else (a blast) just angers it.
	var holder: Variant = source.get(&"holder") if source != null else null
	server_anger(holder if holder is Node3D else (source as Node3D))


## Server: anyone aiming down sights at it for `aim_seconds` provokes it.
func _watch_sights(delta: float) -> void:
	var cone := cos(deg_to_rad(float(config["aim_cone_degrees"])))
	var range_m: float = config["aim_range"]
	var watcher: Node3D = null
	for p in get_tree().get_nodes_in_group(&"players"):
		var player := p as PlayerController
		if player == null or player.get_meta(&"dead", false) or not player.intent().aim:
			continue
		var head := player.get_node_or_null("Head") as Node3D
		if head == null:
			continue
		var to := global_position - head.global_position
		if to.length() > range_m:
			continue
		var forward := -head.global_basis.z
		if forward.normalized().dot(to.normalized()) >= cone:
			watcher = player
			break
	if watcher == null:
		_aimed_for = maxf(_aimed_for - delta, 0.0)
		return
	_aimed_for += delta
	if _aimed_for >= float(config["aim_seconds"]):
		server_anger(watcher)


func is_diving() -> bool:
	return _dive_left >= 0.0


## Holds off diving for `seconds` (tests that watch it circle).
func postpone_dive(seconds: float) -> void:
	_until_dive = seconds


func _next_dive() -> float:
	var range_pair: Array = config["dive_interval_seconds"]
	return _rng.randf_range(float(range_pair[0]), float(range_pair[1]))


## Server: start a dive at the target now (also what the timer does).
func server_dive() -> void:
	_dive_left = float(config["dive_seconds"])
	Net.server_broadcast(&"drone.diving", {"drone": self})


func _step_dive(delta: float) -> void:
	_dive_left -= delta
	var aim := target.global_position + Vector3.UP * 1.1
	var to := aim - global_position
	if to.length() < float(config["dive_trigger_radius"]):
		server_detonate(float(config["dive_blast_radius"]), float(config["dive_damage"]))
		return
	if _dive_left < 0.0 or target.get_meta(&"dead", false):
		# Missed: pull up and go back to circling.
		_dive_left = -1.0
		_until_dive = _next_dive()
		return
	velocity = velocity.move_toward(to.normalized() * float(config["dive_speed"]), float(config["acceleration"]) * delta * 6.0)
	move_and_slide()
	global_basis = global_basis.slerp(Basis.looking_at(to.normalized(), Vector3.UP), 1.0 - exp(-8.0 * delta)).orthonormalized()


func _step_stalk(delta: float) -> void:
	if is_diving() and is_instance_valid(target):
		_step_dive(delta)
		return
	if not is_instance_valid(target):
		velocity = velocity.move_toward(Vector3.ZERO, float(config["acceleration"]) * delta)
		move_and_slide()
		return
	_watch_sights(delta)
	if _angry:
		_calm_in -= delta
		if _calm_in <= 0.0:
			_calm_down()
	if _angry:
		_until_dive -= delta
		if _until_dive <= 0.0 and not target.get_meta(&"dead", false):
			server_dive()
			return
	_until_turn -= delta
	if _until_turn <= 0.0:
		_orbit_direction = -_orbit_direction if _rng.randf() < 0.5 else _orbit_direction
		_until_turn = float(config["direction_change_seconds"]) * _rng.randf_range(0.6, 1.4)
	var radius: float = config["orbit_radius"] if _angry else config["calm_orbit_radius"]
	# On a wide orbit the circle itself would outrun the drone; keep it to what it can fly.
	var turn := minf(float(config["orbit_speed"]), float(config["speed"]) * 0.6 / radius)
	_orbit_angle += turn * _orbit_direction * delta
	var height: float = config["orbit_height"] if _angry else config["calm_orbit_height"]
	var wobble := sin(Time.get_ticks_msec() / 700.0 + get_instance_id()) * 0.8
	var goal := target.global_position + Vector3(cos(_orbit_angle) * radius, height + wobble, sin(_orbit_angle) * radius)
	goal.y = maxf(goal.y, _ground_below(goal) + float(config["min_ground_clearance"]))
	var desired := (goal - global_position).limit_length(float(config["speed"]))
	velocity = velocity.move_toward(desired, float(config["acceleration"]) * delta * 3.0)
	move_and_slide()
	# Face the target, banking a little into its motion.
	var look := target.global_position - global_position
	look.y = 0.0
	if look.length() > 0.1:
		var facing := Basis.looking_at(look.normalized(), Vector3.UP)
		var bank := Basis(Vector3.FORWARD, clampf(-velocity.dot(facing.x) * 0.04, -0.4, 0.4))
		global_basis = global_basis.slerp(facing * bank, 1.0 - exp(-5.0 * delta)).orthonormalized()


func _step_fall(delta: float) -> void:
	_fall_left -= delta
	velocity.y -= _gravity * delta
	rotate_object_local(_tumble.normalized(), _tumble.length() * delta)
	var collided := move_and_slide()
	if collided or _fall_left <= 0.0:
		server_crash()


func _ground_below(at: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 50.0, at + Vector3.DOWN * 200.0, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else -INF


func _on_died(_source: Node) -> void:
	downed = true
	_fall_left = config["fall_seconds"]
	_tumble = Vector3(_rng.randf_range(-3, 3), _rng.randf_range(-6, 6), _rng.randf_range(-3, 3))
	velocity += Vector3(_rng.randf_range(-2, 2), 1.5, _rng.randf_range(-2, 2))


## Server only: the wreck hits the ground and goes up in a small blast.
func server_crash() -> void:
	server_detonate(float(config["crash_radius"]), float(config["crash_damage"]))


## Server only: blows up here, hurting everything within `radius` (full damage at the
## centre, a quarter at the edge), and is gone.
func server_detonate(radius: float, damage: float) -> void:
	set_physics_process(false)
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.exclude = [get_rid()]
	var damaged: Array[HealthComponent] = []
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var collider: Object = hit["collider"]
		var health := HealthComponent.find_on(collider as Node) if collider is Node else null
		if health == null or health == _health or health in damaged:
			continue
		damaged.append(health)
		var holder := health.get_parent() as Node3D
		var distance := holder.global_position.distance_to(global_position) if holder != null else 0.0
		health.server_apply_damage(damage * lerpf(1.0, 0.25, clampf(distance / radius, 0.0, 1.0)), self)
	Net.server_broadcast(&"explosion", {"position": global_position, "radius": radius, "source": null})
	destroyed.emit()
	queue_free()

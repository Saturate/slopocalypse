class_name StalkerDrone
extends CharacterBody3D
## A scout drone that stalks a target: orbits it at a set radius and height, changing
## direction now and then, never hugging the ground. When its health runs out it tumbles
## out of the sky and crashes. All decisions run on the server; rotor spin and the blinking
## light are cosmetic.

signal destroyed

const CONFIG := "res://modules/drones/data/drones.json"
const REQUIRED := {
	"max_health": TYPE_FLOAT, "speed": TYPE_FLOAT, "acceleration": TYPE_FLOAT,
	"orbit_radius": TYPE_FLOAT, "orbit_height": TYPE_FLOAT, "orbit_speed": TYPE_FLOAT,
	"min_ground_clearance": TYPE_FLOAT, "direction_change_seconds": TYPE_FLOAT,
	"fall_seconds": TYPE_FLOAT, "crash_radius": TYPE_FLOAT, "crash_damage": TYPE_FLOAT,
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
	_health.died.connect(_on_died)


func health() -> HealthComponent:
	return _health


func _process(delta: float) -> void:
	# Cosmetic: rotors spin (slower once downed), light blinks.
	var spin := 40.0 if not downed else 8.0
	for rotor in _rotors.get_children():
		(rotor as Node3D).rotate_y(spin * delta)
	_light.light_energy = 2.5 if fmod(Time.get_ticks_msec() / 1000.0, 0.8) < 0.15 else 0.0


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if downed:
		_step_fall(delta)
	else:
		_step_stalk(delta)


func _step_stalk(delta: float) -> void:
	if not is_instance_valid(target):
		velocity = velocity.move_toward(Vector3.ZERO, float(config["acceleration"]) * delta)
		move_and_slide()
		return
	_until_turn -= delta
	if _until_turn <= 0.0:
		_orbit_direction = -_orbit_direction if _rng.randf() < 0.5 else _orbit_direction
		_until_turn = float(config["direction_change_seconds"]) * _rng.randf_range(0.6, 1.4)
	_orbit_angle += float(config["orbit_speed"]) * _orbit_direction * delta
	var radius: float = config["orbit_radius"]
	var wobble := sin(Time.get_ticks_msec() / 700.0 + get_instance_id()) * 0.8
	var goal := target.global_position + Vector3(cos(_orbit_angle) * radius, float(config["orbit_height"]) + wobble, sin(_orbit_angle) * radius)
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
	set_physics_process(false)
	Net.server_broadcast(&"explosion", {"position": global_position, "radius": float(config["crash_radius"]), "source": null})
	destroyed.emit()
	queue_free()

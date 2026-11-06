class_name CarController
extends VehicleBody3D
## Drives a VehicleBody3D from CarIntent. Holds who is driving; entering and leaving are
## announced on the EventBus so the player module handles its own node.

const CONFIG := "res://modules/car/data/car.json"
const REQUIRED := {
	"mass": TYPE_FLOAT,
	"engine_force": TYPE_FLOAT,
	"reverse_force": TYPE_FLOAT,
	"brake_force": TYPE_FLOAT,
	"top_speed": TYPE_FLOAT,
	"max_steer_degrees": TYPE_FLOAT,
	"steer_speed": TYPE_FLOAT,
	"enter_distance": TYPE_FLOAT,
}

@export var intent_path: NodePath
@export var exit_point_path: NodePath
@export var camera_path: NodePath

var config: Dictionary = {}
## The node currently driving, or null.
var driver: Node3D

var _intent: CarIntent
var _exit_point: Marker3D


## The car's key bindings from data, for registering before any car exists on a client.
static func bindings() -> Dictionary:
	var data: Variant = Data.load_json(CONFIG)
	return (data as Dictionary).get("bindings", {}) if data is Dictionary else {}


func _ready() -> void:
	_intent = get_node(intent_path)
	_exit_point = get_node(exit_point_path)
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not Data.require(CONFIG, data, REQUIRED):
		set_physics_process(false)
		return
	config = data
	mass = config["mass"]


func intent() -> CarIntent:
	return _intent


func camera() -> Camera3D:
	return get_node(camera_path)


func speed() -> float:
	return linear_velocity.length()


## Forward speed along the car's nose; negative when reversing. VehicleBody3D drives
## along +Z, unlike the usual Godot -Z forward, so the whole car uses +Z as its nose.
func forward_speed() -> float:
	return linear_velocity.dot(global_transform.basis.z)


func can_enter(who: Node3D) -> bool:
	return driver == null and who.global_position.distance_to(global_position) <= float(config["enter_distance"])


func enter(who: Node3D) -> void:
	driver = who
	_intent.clear()
	# A settled car falls asleep and engine_force alone does not wake it.
	can_sleep = false
	sleeping = false
	EventBus.publish(&"car.entered", {"player": who, "car": self})


func exit_car() -> void:
	if driver == null:
		return
	var who := driver
	driver = null
	_intent.clear()
	can_sleep = true
	EventBus.publish(&"car.exited", {"player": who, "car": self, "position": exit_position()})


## Beside the driver door, lifted so the player drops onto the ground instead of into it.
func exit_position() -> Vector3:
	return _exit_point.global_position + Vector3.UP * 0.5


func _physics_process(delta: float) -> void:
	if driver != null and _intent.consume_exit():
		exit_car()
	var throttle := _intent.throttle if driver != null else 0.0
	var force := 0.0
	if throttle > 0.0 and forward_speed() < float(config["top_speed"]):
		force = throttle * float(config["engine_force"])
	elif throttle < 0.0:
		force = throttle * float(config["reverse_force"])
	engine_force = force
	var wants_brake := _intent.brake or driver == null
	brake = float(config["brake_force"]) if wants_brake else 0.0
	var target := -_intent.steer * deg_to_rad(float(config["max_steer_degrees"]))
	steering = move_toward(steering, target, float(config["steer_speed"]) * delta)

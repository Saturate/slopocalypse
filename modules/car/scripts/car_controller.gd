class_name CarController
extends VehicleBody3D
## Drives a VehicleBody3D from CarIntent. Only the server simulates; clients see the synced
## transform. Two seats, driver and passenger; entering and leaving are broadcast to every
## instance so each module (player parking, car input, terrain viewer) reacts everywhere.
## A car left on its roof or side rights itself after a moment.

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
	"high_speed_steer_share": TYPE_FLOAT,
	"downforce": TYPE_FLOAT,
	"flip_seconds": TYPE_FLOAT,
}
const DRIVER := &"driver"
const PASSENGER := &"passenger"
## Upright enough to drive: the car's up axis at least this far towards the sky.
const UPRIGHT := 0.4
## Slower than this counts as stuck for flipping back.
const STUCK_SPEED := 2.0
## A righted car is put down this far above where it was.
const RIGHT_LIFT := 1.0
## Engine force fades out over this last share of top speed instead of cutting off.
const POWER_FADE := 0.15
## A standing person, for checking there is room beside a door.
const PERSON_RADIUS := 0.35
const PERSON_HEIGHT := 1.7

@export var intent_path: NodePath
@export var exit_point_path: NodePath
@export var passenger_exit_path: NodePath
@export var camera_path: NodePath

var config: Dictionary = {}
## The node currently driving, or null.
var driver: Node3D
## The node in the other seat, or null.
var passenger: Node3D

var _intent: CarIntent
var _exit_point: Marker3D
var _passenger_exit: Marker3D
var _stuck_for := 0.0


## The car's key bindings from data, for registering before any car exists on a client.
static func bindings() -> Dictionary:
	var data: Variant = Data.load_json(CONFIG)
	return (data as Dictionary).get("bindings", {}) if data is Dictionary else {}


func _ready() -> void:
	_intent = get_node(intent_path)
	_exit_point = get_node(exit_point_path)
	_passenger_exit = get_node_or_null(passenger_exit_path)
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


func seat_of(who: Node3D) -> StringName:
	if who == null:
		return &""
	if who == driver:
		return DRIVER
	if who == passenger:
		return PASSENGER
	return &""


func can_enter(who: Node3D) -> bool:
	if seat_of(who) != &"" or (driver != null and passenger != null):
		return false
	return who.global_position.distance_to(global_position) <= float(config["enter_distance"])


## The driver's seat if it is free, otherwise the passenger's.
func enter(who: Node3D) -> void:
	var seat := DRIVER if driver == null else PASSENGER
	if seat == DRIVER:
		driver = who
		_intent.clear()
		# A settled car falls asleep and engine_force alone does not wake it.
		can_sleep = false
		sleeping = false
	else:
		passenger = who
	Net.server_broadcast(&"car.entered", {"player": who, "car": self, "seat": seat})


## Lets `who` out (the driver when not given) beside their own door.
func exit_car(who: Node3D = null) -> void:
	if who == null:
		who = driver
	var seat := seat_of(who)
	if seat == &"":
		return
	var at := exit_position(seat)
	if seat == DRIVER:
		driver = null
		_intent.clear()
		can_sleep = true
	else:
		passenger = null
	Net.server_broadcast(&"car.exited", {"player": who, "car": self, "seat": seat, "position": at})


## Beside the seat's door, lifted so the player drops onto the ground instead of into it;
## the other door when something solid stands there, and over the roof when both are blocked.
func exit_position(seat: StringName = DRIVER) -> Vector3:
	var own := _exit_point if seat == DRIVER or _passenger_exit == null else _passenger_exit
	var other := _passenger_exit if own == _exit_point else _exit_point
	for door: Marker3D in [own, other]:
		if door == null:
			continue
		var at := door.global_position + Vector3.UP * 0.5
		if not is_inside_tree() or _room_at(at):
			return at
	return global_position + Vector3.UP * (RIGHT_LIFT + 1.5)


## Room for a standing person with their feet at `at`.
func _room_at(at: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = PERSON_RADIUS
	capsule.height = PERSON_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * (PERSON_HEIGHT / 2.0 + 0.05))
	query.collision_mask = PhysicsLayers.SOLID
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _physics_process(delta: float) -> void:
	var prof := Prof.start()
	_physics_tick(delta)
	Prof.stop(&"car/car_controller:physics", prof)


func _physics_tick(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if driver != null and _intent.consume_exit():
		exit_car(driver)
	if passenger != null and _intent.consume_passenger_exit():
		exit_car(passenger)
	var top: float = config["top_speed"]
	var ahead := forward_speed()
	var throttle := _intent.throttle if driver != null else 0.0
	var force := 0.0
	if throttle > 0.0:
		# Full power until near top speed, then fading out, so it doesn't stutter at the limit.
		var fade := clampf((top - ahead) / (top * POWER_FADE), 0.0, 1.0)
		force = throttle * float(config["engine_force"]) * fade
	elif throttle < 0.0:
		force = throttle * float(config["reverse_force"])
	engine_force = force
	var wants_brake := _intent.brake or driver == null
	brake = float(config["brake_force"]) if wants_brake else 0.0
	# Less lock at speed: full lock for parking, a gentler turn near top speed, so a tap
	# doesn't spin it out or roll it.
	var share := lerpf(1.0, float(config["high_speed_steer_share"]), clampf(absf(ahead) / top, 0.0, 1.0))
	var target := -_intent.steer * deg_to_rad(float(config["max_steer_degrees"])) * share
	steering = move_toward(steering, target, float(config["steer_speed"]) * delta)
	# Grip that grows with speed keeps it planted over crests.
	apply_central_force(-global_transform.basis.y * float(config["downforce"]) * linear_velocity.length_squared())
	_right_when_stuck(delta)


## On its roof or side and barely moving for `flip_seconds`: put back on its wheels where it
## is, keeping its heading.
func _right_when_stuck(delta: float) -> void:
	if freeze or global_transform.basis.y.y >= UPRIGHT or linear_velocity.length() > STUCK_SPEED:
		_stuck_for = 0.0
		return
	_stuck_for += delta
	if _stuck_for < float(config["flip_seconds"]):
		return
	_stuck_for = 0.0
	var heading := global_transform.basis.z
	heading.y = 0.0
	var basis := Basis.looking_at(-heading.normalized()) if heading.length() > 0.01 else Basis.IDENTITY
	global_transform = Transform3D(basis, global_position + Vector3.UP * RIGHT_LIFT)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	Log.info(&"car", "%s was stuck on its side; put it back on its wheels" % name)

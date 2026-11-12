extends Node3D
## Client-only looks: puts the voxel body (VoxCar) here and a voxel wheel on each wheel, made
## from car.json when the car appears. The server never builds meshes. No class_name and no
## autoloads, so the scene builder can attach it.
##
## A client's copy of the car is frozen and only follows the transform the server syncs, so
## nothing moves its wheels. Here they move from what the car is seen to do: they spin with
## the distance it rolls, the front ones turn with how sharply it turns at its speed, and each
## sits on the ground under it within its spring travel, so wheels drop into dips and push up
## over bumps. Where the car is simulated (the server, in-process tests) its physics moves the
## wheels and this leaves them alone.

const CONFIG := "res://modules/car/data/car.json"

## Generated once per run and shared by every car.
static var _body: ArrayMesh
static var _wheel: ArrayMesh
## How quickly the shown steering follows the turn it reads (per second).
const STEER_FOLLOW := 10.0

## On for frozen copies (clients); a capture may switch it on to see it in-process.
var animate := false
var _radius := 0.38
var _rest := 0.3
var _travel := 0.25
var _wheelbase := 2.7
var _max_steer := deg_to_rad(30.0)
## Per wheel: {wheel, mesh, lay (the mesh's resting transform on its axle), front, angle}.
var _wheels: Array[Dictionary] = []
var _steer := 0.0
var _last := Transform3D()
var _has_last := false


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if not cfg is Dictionary:
		return
	var c: Dictionary = cfg
	if _body == null:
		var looks: Dictionary = c.get("looks", {})
		var values := {
			"seed": looks.get("seed", 1.0),
			"paint": looks.get("paint", 0.0),
			"wear": looks.get("wear", 0.5),
			"length": c["length"],
			"width": c["width"],
			"wheel_x": c["wheel_x"],
			"wheel_z": c["wheel_z"],
			"wheel_radius": c["wheel_radius"],
		}
		_body = VoxGenerator.to_mesh(VoxCar.new().build(values))
		_wheel = VoxGenerator.to_mesh(VoxCar.wheel(float(c["wheel_radius"]), float(c["wheel_width"])))
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _body
	add_child(body)
	var width: float = c["wheel_width"]
	for child in get_parent().get_children():
		if child is VehicleWheel3D:
			var mesh := child.get_node_or_null("Mesh") as MeshInstance3D
			if mesh == null:
				continue
			mesh.mesh = _wheel
			# The wheel is built standing on y from its base; lay it on its axle (x), centred,
			# with the hub facing outwards on each side.
			var outward := signf(child.position.x)
			mesh.transform = Transform3D(Basis(Vector3.BACK, -outward * PI / 2.0), Vector3(-outward * width / 2.0, 0.0, 0.0))
			_wheels.append({"wheel": child, "mesh": mesh, "lay": mesh.transform, "front": (child as VehicleWheel3D).use_as_steering, "angle": 0.0})
	_radius = float(c["wheel_radius"])
	_rest = float(c.get("suspension_rest_length", _rest))
	_travel = float(c.get("suspension_travel", _travel))
	_wheelbase = float(c.get("wheel_z", _wheelbase / 2.0)) * 2.0
	_max_steer = deg_to_rad(float(c.get("max_steer_degrees", 30.0)))
	var car := get_parent() as RigidBody3D
	animate = car != null and car.freeze and not multiplayer.is_server()


func _physics_process(delta: float) -> void:
	if not animate or _wheels.is_empty() or delta <= 0.0:
		return
	var t := Prof.start()
	_move_wheels(delta)
	Prof.stop(&"car/car_looks:wheels", t)


func _move_wheels(delta: float) -> void:
	var car := get_parent() as Node3D
	var now := car.global_transform
	if not _has_last:
		_last = now
		_has_last = true
	# The car drives along +Z (VehicleBody3D's nose).
	var nose := now.basis.z.normalized()
	var rolled := (now.origin - _last.origin).dot(nose)
	var turned := signed_turn(_last.basis.z, nose, now.basis.y)
	_last = now
	_steer = lerpf(_steer, steer_for(rolled / delta, turned / delta, _wheelbase, _max_steer), 1.0 - exp(-STEER_FOLLOW * delta))
	var space := car.get_world_3d().direct_space_state
	var down := -now.basis.y.normalized()
	for w: Dictionary in _wheels:
		var wheel: Node3D = w["wheel"]
		w["angle"] = fmod(float(w["angle"]) + rolled / _radius, TAU)
		var mount := wheel.global_position
		var query := PhysicsRayQueryParameters3D.create(mount, mount + down * (_rest + _travel + _radius))
		if car is CollisionObject3D:
			query.exclude = [(car as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(query)
		var reach := INF if hit.is_empty() else mount.distance_to(hit["position"])
		var drop := hub_drop(reach, _radius, _rest, _travel)
		var steer := _steer if bool(w["front"]) else 0.0
		# Hub down on its spring, turned for steering, spun about its axle (x), then laid on it.
		(w["mesh"] as Node3D).transform = Transform3D(Basis(Vector3.UP, steer), Vector3.DOWN * drop) * Transform3D(Basis(Vector3.RIGHT, float(w["angle"])), Vector3.ZERO) * (w["lay"] as Transform3D)


## How far below its mount a wheel's hub sits: where the tyre meets ground `reach` metres
## down (INF: nothing under it), kept within the spring's rest length plus or minus its travel.
static func hub_drop(reach: float, radius: float, rest: float, travel: float) -> float:
	return clampf(reach - radius, rest - travel, rest + travel)


## The steering angle that turns a car with `wheelbase` at `turn_rate` (radians per second)
## while it rolls at `speed` (metres per second along its nose), within `max_steer`. Standing
## still it reads nothing. Same sign as the turn, flipped when reversing.
static func steer_for(speed: float, turn_rate: float, wheelbase: float, max_steer: float) -> float:
	if absf(speed) < 0.3:
		return 0.0
	return clampf(atan(wheelbase * turn_rate / speed), -max_steer, max_steer)


## The signed angle from `from` to `to` about `up` (positive turning left, as seen from above).
static func signed_turn(from: Vector3, to: Vector3, up: Vector3) -> float:
	var a := Vector3(from.x, 0.0, from.z) if up.is_zero_approx() else from - up * from.dot(up)
	var b := to - up * to.dot(up)
	if a.is_zero_approx() or b.is_zero_approx():
		return 0.0
	return a.signed_angle_to(b, up.normalized())

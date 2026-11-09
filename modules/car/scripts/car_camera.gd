extends Camera3D
## Client-only chase camera. Placed behind the car every frame, but lagging so speed and
## turns read, looking a little ahead of the nose, widening with speed, and pulled in where
## a wall or the ground is between it and the car. The mouse swings it round the car; it
## drifts back behind after a moment. No class_name and no autoloads, so the scene builder
## can attach it.

const CONFIG := "res://modules/car/data/car.json"

var _cfg: Dictionary = {}
var _top_speed := 25.0
var _yaw := 0.0
var _idle := 0.0
var _placed := false


func _ready() -> void:
	top_level = true
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if data is Dictionary:
		_cfg = (data as Dictionary).get("camera", {})
		_top_speed = float((data as Dictionary).get("top_speed", 25.0))
	# The car scene carries this camera everywhere, the server included; only a screen needs
	# it every frame (tests still call place() directly).
	if _cfg.is_empty() or DisplayServer.get_name() == "headless":
		set_process(false)


func _process(delta: float) -> void:
	var prof := Prof.start()
	_process_tick(delta)
	Prof.stop(&"car/car_camera:frame", prof)


func _process_tick(delta: float) -> void:
	if not current:
		_placed = false
		return
	place(delta)


## Moves the camera one frame towards where it wants to be (snaps on the first frame).
func place(delta: float) -> void:
	var car := get_parent() as Node3D
	var forward := car.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.1 else Vector3.BACK
	_idle += delta
	if _idle > float(_cfg["orbit_return_seconds"]):
		_yaw = lerpf(_yaw, 0.0, 1.0 - exp(-3.0 * delta))
	var back := forward.rotated(Vector3.UP, _yaw)
	var pivot := car.global_position + Vector3.UP * float(_cfg["look_height"])
	var want := car.global_position - back * float(_cfg["distance"]) + Vector3.UP * float(_cfg["height"])
	var clear := _clear_of_walls(car, pivot, want)
	if not _placed:
		global_position = clear
		_placed = true
	else:
		global_position = global_position.lerp(want, 1.0 - exp(-float(_cfg["follow_rate"]) * delta))
		# Never behind a wall, even for a frame: pull straight in, ease back out.
		if clear != want and pivot.distance_to(global_position) > pivot.distance_to(clear):
			global_position = clear
	var look := pivot + forward * float(_cfg["look_ahead"])
	if not global_position.is_equal_approx(look):
		look_at(look)
	var speed := (car as RigidBody3D).linear_velocity.length() if car is RigidBody3D else 0.0
	var target_fov := lerpf(float(_cfg["fov"]), float(_cfg["fov_at_top_speed"]), clampf(speed / _top_speed, 0.0, 1.0))
	fov = lerpf(fov, target_fov, 1.0 - exp(-2.0 * delta))


func _unhandled_input(event: InputEvent) -> void:
	if not current or not event is InputEventMouseMotion:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	_yaw -= (event as InputEventMouseMotion).relative.x * float(_cfg["orbit_sensitivity"])
	_yaw = wrapf(_yaw, -PI, PI)
	_idle = 0.0


## Swings the camera round by `radians` (as the mouse does).
func orbit(radians: float) -> void:
	_yaw = wrapf(_yaw + radians, -PI, PI)
	_idle = 0.0


## Pulls the camera in to just short of anything solid between the car and where it wants to be.
func _clear_of_walls(car: Node3D, from: Vector3, to: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if car is CollisionObject3D:
		exclude.append((car as CollisionObject3D).get_rid())
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.SOLID, exclude))
	if hit.is_empty():
		return to
	var at: Vector3 = hit["position"]
	return at + (from - at).normalized() * float(_cfg["clearance"])

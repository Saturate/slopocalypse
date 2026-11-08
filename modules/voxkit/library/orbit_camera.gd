class_name OrbitCamera
extends Camera3D
## Turns around a target: drag with the left mouse button to orbit, wheel to zoom. Turns on
## its own when `turntable` is set.

const DRAG_SPEED := 0.008
const ZOOM_STEP := 1.12
const TURNTABLE_SPEED := 0.35
const PITCH_LIMIT := Vector2(-1.45, 0.25)

var target := Vector3.ZERO
var distance := 8.0
var yaw := 0.7
var pitch := -0.35
var turntable := true
var _dragging := false


func frame(aabb: AABB) -> void:
	target = aabb.get_center()
	distance = maxf(aabb.size.length() * 1.15, 1.5)
	_place()


func handle(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		if b.button_index == MOUSE_BUTTON_LEFT:
			_dragging = b.pressed
		elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(distance / ZOOM_STEP, 0.5)
		elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(distance * ZOOM_STEP, 400.0)
	elif event is InputEventMouseMotion and _dragging:
		var m := event as InputEventMouseMotion
		yaw -= m.relative.x * DRAG_SPEED
		pitch = clampf(pitch - m.relative.y * DRAG_SPEED, PITCH_LIMIT.x, PITCH_LIMIT.y)


func _process(delta: float) -> void:
	if turntable and not _dragging:
		yaw += TURNTABLE_SPEED * delta
	_place()


func _place() -> void:
	var offset := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * distance
	look_at_from_position(target + offset, target)

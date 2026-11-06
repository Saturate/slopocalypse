class_name PlayerCameraFeel
extends Node
## Client-only camera feel for the local player: FOV widens while sprinting and the view
## bobs with each step. Purely cosmetic, never affects movement or shots, never on the server.

var player: PlayerController
var camera: Camera3D

var _distance := 0.0
var _fov_bonus := 0.0
var _bob := Vector3.ZERO


func _process(delta: float) -> void:
	var cfg := player.config
	var target_bonus: float = cfg["fov_sprint_bonus"] if (player.is_sprinting() or player.is_sliding()) else 0.0
	_fov_bonus = lerpf(_fov_bonus, target_bonus, 1.0 - exp(-8.0 * delta))
	camera.fov = float(cfg["fov"]) + _fov_bonus

	var speed := player.horizontal_speed() if player.is_on_floor() and player.mode == PlayerController.Mode.NORMAL else 0.0
	_distance += speed * delta
	# One full bob cycle every two steps: down on each footfall.
	var phase := _distance / float(cfg["bob_step_length"]) * TAU
	var strength := clampf(speed / float(cfg["sprint_speed"]), 0.0, 1.0)
	var amp: float = cfg["bob_amplitude"]
	var target := Vector3(cos(phase * 0.5) * amp * 0.6, -absf(sin(phase * 0.5)) * amp, 0.0) * strength
	_bob = _bob.lerp(target, 1.0 - exp(-12.0 * delta))
	camera.position = _bob

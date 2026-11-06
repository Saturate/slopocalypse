extends Node3D
## Capture setup: the player walks and turns across the world, seen by a chase camera
## so a reviewer sees both the player and the terrain.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const CHASE_OFFSET := Vector3(2.5, 2.5, 6.0)

var _player: PlayerController
var _camera := Camera3D.new()
var _ticks := 0


func _ready() -> void:
	add_child((load(WORLD) as PackedScene).instantiate())
	_player = (load(PLAYER) as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	add_child(_camera)
	_camera.current = true


func _physics_process(_delta: float) -> void:
	_ticks += 1
	var intent := _player.intent()
	intent.move = Vector2(0.0, 1.0) if _ticks > 15 else Vector2.ZERO
	intent.sprint = _ticks > 60
	intent.look_delta.x += 0.01
	var target := _player.global_transform * CHASE_OFFSET
	_camera.global_position = target
	_camera.look_at(_player.global_position + Vector3.UP * 1.2)

extends Node3D
## Capture setup: the third-person soldier seen from the side as it walks, sprints,
## crouches and slides, with the held rifle and aim pitch.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"

var _player: PlayerController
var _camera := Camera3D.new()
var _ticks := 0


func _ready() -> void:
	# Voxel terrain streams in; wait for the spawn area before dropping anything onto it.
	await VoxelWorld.add_and_wait(self, WORLD)
	# The chase camera would end up inside trees; this capture is about the body.
	var scenery := find_child("Scenery", true, false) as Node3D
	if scenery != null:
		scenery.visible = false
	_player = (load(PLAYER) as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3(0.0, 0.1, 6.0)
	var animator := PlayerBodyAnimator.new()
	animator.player = _player
	_player.add_child(animator)
	var held := MeshInstance3D.new()
	held.mesh = RifleMesh.rifle()
	PlayerBody.weapon_socket(_player).add_child(held)
	add_child(_camera)
	_camera.current = true
	_camera.fov = 50.0


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	_ticks += 1
	var intent := _player.intent()
	intent.move = Vector2(0.0, 1.0) if _ticks > 10 and _ticks < 260 else Vector2.ZERO
	intent.sprint = _ticks > 90
	intent.crouch = _ticks > 200
	# Look up a little late in the run to show the chest following the aim.
	if _ticks > 140 and _ticks < 170:
		intent.look_delta.y -= 0.01
	var side := _player.global_transform.basis.x
	_camera.global_position = _player.global_position + side * 4.5 + Vector3.UP * 1.3 + _player.global_transform.basis.z * -0.5
	_camera.look_at(_player.global_position + Vector3.UP * 0.95)

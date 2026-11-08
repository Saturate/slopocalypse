extends Node3D
## Capture setup: another player seen from the front, leaning left, then right, rifle up:
## head and shoulders should tilt out to the side together with the gun.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"

var _player: PlayerController
var _camera := Camera3D.new()
var _ticks := 0


func _ready() -> void:
	await VoxelWorld.add_and_wait(self, WORLD)
	var scenery := find_child("Scenery", true, false) as Node3D
	if scenery != null:
		scenery.visible = false
	add_child((load(MODULE) as GDScript).new())
	_player = (load(PLAYER) as PackedScene).instantiate()
	_player.add_to_group(&"players")
	add_child(_player)
	_player.global_position = Vector3(0.0, 0.1, 0.0)
	EventBus.publish(&"player.spawned", {"player": _player, "local": false})
	var animator := PlayerBodyAnimator.new()
	animator.name = "BodyAnimator"
	animator.player = _player
	_player.add_child(animator)
	add_child(_camera)
	_camera.current = true
	_camera.fov = 40.0


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	_ticks += 1
	var intent := _player.intent()
	intent.aim = true
	intent.lean = -1 if _ticks > 30 and _ticks < 100 else (1 if _ticks > 110 and _ticks < 180 else 0)

	var at := _player.global_position
	var front_right := _player.global_transform.basis * Vector3(0.0, 0.0, -3.2)
	_camera.global_position = at + front_right + Vector3.UP * 1.6
	_camera.look_at(at + Vector3.UP * 1.45)




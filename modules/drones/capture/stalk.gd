extends Node3D
## Capture setup: a stalker drone circling the player, seen from behind the player.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/drones/drones_module.gd"

var _player: PlayerController
var _drone: StalkerDrone
var _camera := Camera3D.new()


func _ready() -> void:
	await VoxelWorld.add_and_wait(self, WORLD)
	_player = (load(PLAYER) as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3(0, 0.2, 0)
	var module: Node = (load(MODULE) as GDScript).new()
	add_child(module)
	_drone = module.server_spawn(_player)
	_drone.global_position = Vector3(10, 7, -8)
	add_child(_camera)
	_camera.current = true
	_camera.fov = 70.0


func _process(_delta: float) -> void:
	if _drone == null or not is_instance_valid(_drone):
		return
	_camera.global_position = _player.global_position + Vector3(0, 1.7, 3.0)
	_camera.look_at(_drone.global_position)

extends Node3D
## Capture setup: another player seen close from the right with one of the new pistols
## drawn (`-- --pistol=fn57`, `deagle` or `python`), raising it from the hip to aiming.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"
const BUILDS := {"fn57": "fn57_standard", "deagle": "deagle_standard", "python": "python_standard"}

var _player: PlayerController
var _camera := Camera3D.new()
var _ticks := 0


func _ready() -> void:
	var pistol := "fn57"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pistol="):
			pistol = arg.trim_prefix("--pistol=")
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	var scenery := find_child("Scenery", true, false) as Node3D
	if scenery != null:
		scenery.visible = false
	add_child((load(MODULE) as GDScript).new())
	EventBus.publish(&"weapons.build_changed", {"peer": 1, "build": GunAssembly.build(str(BUILDS.get(pistol, "fn57_standard")))})
	_player = (load(PLAYER) as PackedScene).instantiate()
	_player.add_to_group(&"players")
	add_child(_player)
	_player.global_position = VoxelWorld.spawn_of(world, Vector3(0.0, 0.1, 0.0))
	EventBus.publish(&"player.spawned", {"player": _player, "local": false})
	var animator := PlayerBodyAnimator.new()
	animator.name = "BodyAnimator"
	animator.player = _player
	_player.add_child(animator)
	add_child(_camera)
	_camera.current = true
	_camera.fov = 30.0


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	_ticks += 1
	var intent := _player.intent()
	if _ticks == 5:
		intent.weapon_2 = true
	intent.aim = _ticks > 160
	var held := ShotEffects.held_rifle(_player)
	var at := held.global_position if held != null else _player.global_position + Vector3.UP * 1.4
	var right := _player.global_transform.basis * Vector3(1.0, 0.15, 0.05)
	_camera.global_position = at + right
	_camera.look_at(at)

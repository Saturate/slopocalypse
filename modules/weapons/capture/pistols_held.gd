extends Node3D
## Capture setup: first person with one of the new pistols drawn (2), `-- --pistol=fn57`,
## `deagle` or `python` (the Five-seveN by default): from the hip, then aimed at a dummy and
## fired a few times; the revolver then reloads a round at a time.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const DUMMY := "res://modules/training/scenes/dummy.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"
const BUILDS := {"fn57": "fn57_standard", "deagle": "deagle_standard", "python": "python_standard"}

var _player: PlayerController
var _ticks := 0


func _ready() -> void:
	var pistol := "fn57"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pistol="):
			pistol = arg.trim_prefix("--pistol=")
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	add_child((load(MODULE) as GDScript).new())
	# Known before the player spawns, so the pistol arrives loaded.
	EventBus.publish(&"weapons.build_changed", {"peer": 1, "build": GunAssembly.build(str(BUILDS.get(pistol, "fn57_standard")))})
	_player = (load(PLAYER) as PackedScene).instantiate()
	_player.add_to_group(&"players")
	add_child(_player)
	_player.global_position = VoxelWorld.spawn_of(world, Vector3(0.0, 0.1, 0.0))
	EventBus.publish(&"player.spawned", {"player": _player, "local": true})
	var animator := PlayerBodyAnimator.new()
	animator.name = "BodyAnimator"
	animator.player = _player
	_player.add_child(animator)
	var feel := PlayerCameraFeel.new()
	feel.player = _player
	feel.camera = _player.get_node("Head/Camera")
	_player.add_child(feel)
	PlayerBody.first_person(_player.get_node("Body"))
	(_player.get_node("Head/Camera") as Camera3D).current = true
	var dummy: Node3D = (load(DUMMY) as PackedScene).instantiate()
	add_child(dummy)
	dummy.global_position = VoxelWorld.spawn_of(world, Vector3(0.0, 0.0, -12.0))


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	_ticks += 1
	var intent := _player.intent()
	if _ticks == 5:
		intent.weapon_2 = true
	intent.aim = _ticks > 90 and _ticks < 260
	# Single taps while aimed, far enough apart for the heaviest kick to settle.
	intent.fire = _ticks > 130 and _ticks < 250 and (_ticks % 40) < 2
	if _ticks == 262:
		intent.reload = true

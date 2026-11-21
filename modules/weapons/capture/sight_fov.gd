extends Node3D
## Capture setup (#376): first person at three field-of-view settings, -10, 0 and +20 degrees,
## at the hip, then the same three aimed down the sight. Run it with --frames 180 --sheet 6:
## the top row is the hip, the bottom row aimed, and the gun and sight should look the same
## size and sit in the same place across each row while the world around them widens.
## `-- --gun=pistol` holds the pistol instead of the rifle.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const DUMMY := "res://modules/training/scenes/dummy.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"
const OFFSETS: Array[float] = [-10.0, 0.0, 20.0]
## Frames per view; the contact sheet grabs the last frame of each.
const VIEW_FRAMES := 30

var _player: PlayerController
var _frame := 0
var _pistol := false


func _ready() -> void:
	_pistol = OS.get_cmdline_user_args().has("--gun=pistol")
	await VoxelWorld.add_and_wait(self, WORLD)
	add_child((load(MODULE) as GDScript).new())
	_player = (load(PLAYER) as PackedScene).instantiate()
	_player.add_to_group(&"players")
	add_child(_player)
	_player.global_position = Vector3(0.0, 0.1, 0.0)
	EventBus.publish(&"player.spawned", {"player": _player, "local": true})
	var animator := PlayerBodyAnimator.new()
	animator.name = "BodyAnimator"
	animator.player = _player
	_player.add_child(animator)
	var feel := PlayerCameraFeel.new()
	feel.name = "CameraFeel"
	feel.player = _player
	feel.camera = _player.get_node("Head/Camera")
	_player.add_child(feel)
	PlayerBody.first_person(_player.get_node("Body"))
	(_player.get_node("Head/Camera") as Camera3D).current = true
	var dummy: Node3D = (load(DUMMY) as PackedScene).instantiate()
	add_child(dummy)
	dummy.global_position = Vector3(0.0, 0.0, -12.0)
	_player.intent().weapon_2 = _pistol


## Counted from the first frame, like the capture tool's grabs, so view i is up when frame
## (i + 1) * VIEW_FRAMES is grabbed even if the world took a while to load.
func _process(_delta: float) -> void:
	_frame += 1
	var view := clampi((_frame - 1) / VIEW_FRAMES, 0, OFFSETS.size() * 2 - 1)
	Settings.set_value("fov_offset", OFFSETS[view % OFFSETS.size()])
	if _player != null:
		_player.intent().aim = view >= OFFSETS.size()

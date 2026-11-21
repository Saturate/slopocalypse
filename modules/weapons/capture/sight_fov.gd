extends Node3D
## Capture setup (#376): first person at three field-of-view settings, -10, 0 and +20 degrees,
## at the hip, then the same three aimed down the sight. Run it with --frames 180 --sheet 6:
## the top row is the hip, the bottom row aimed. From the default view (middle) to the wider
## one (right) the gun and sight should look the same size and sit in the same place while the
## world around them widens; the narrower view (left) keeps the gun where it was set up to sit
## (the arms reach no further), so there it looks a little bigger.
## `-- --gun=pistol` holds the pistol instead of the rifle. `-- --offsets=0,30` picks other
## field-of-view settings; `-- --sprint` sprints forward through the hip views, so the sprint
## widening adds to the setting (aiming stops a sprint, so the aimed row stands).

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const DUMMY := "res://modules/training/scenes/dummy.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"
const DEFAULT_OFFSETS: Array[float] = [-10.0, 0.0, 20.0]
const DUMMY_DISTANCE := 12.0
## Far enough that a sprint through the hip views stops short of the dummy.
const SPRINT_DUMMY_DISTANCE := 30.0
## Frames per view; the contact sheet grabs the last frame of each.
const VIEW_FRAMES := 30

var _player: PlayerController
var _frame := 0
var _pistol := false
var _sprint := false
var _offsets: Array[float] = DEFAULT_OFFSETS.duplicate()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_pistol = args.has("--gun=pistol")
	_sprint = args.has("--sprint")
	for arg in args:
		if arg.begins_with("--offsets="):
			_offsets.clear()
			for value in arg.trim_prefix("--offsets=").split(",", false):
				_offsets.append(value.to_float())
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	add_child((load(MODULE) as GDScript).new())
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
	feel.name = "CameraFeel"
	feel.player = _player
	feel.camera = _player.get_node("Head/Camera")
	_player.add_child(feel)
	PlayerBody.first_person(_player.get_node("Body"))
	(_player.get_node("Head/Camera") as Camera3D).current = true
	var dummy: Node3D = (load(DUMMY) as PackedScene).instantiate()
	add_child(dummy)
	var distance := SPRINT_DUMMY_DISTANCE if _sprint else DUMMY_DISTANCE
	dummy.global_position = VoxelWorld.spawn_of(world, Vector3(0.0, 0.0, -distance))
	_player.intent().weapon_2 = _pistol


## Counted from the first frame, like the capture tool's grabs, so view i is up when frame
## (i + 1) * VIEW_FRAMES is grabbed even if the world took a while to load.
func _process(_delta: float) -> void:
	_frame += 1
	var view := clampi((_frame - 1) / VIEW_FRAMES, 0, _offsets.size() * 2 - 1)
	Settings.set_value("fov_offset", _offsets[view % _offsets.size()])
	if _player != null:
		var aimed := view >= _offsets.size()
		_player.intent().aim = aimed
		_player.intent().sprint = _sprint and not aimed
		_player.intent().move = Vector2(0.0, 1.0) if _sprint and not aimed else Vector2.ZERO

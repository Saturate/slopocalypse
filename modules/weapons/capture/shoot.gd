extends Node3D
## Capture setup: first-person view firing bursts at a training dummy until it falls,
## with the HUD (crosshair, hit marker, ammo) and tracers visible. The rifle on screen is
## the one in the body's hands, held by the player's own arms.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const DUMMY := "res://modules/training/scenes/dummy.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"

var _player: PlayerController
var _ticks := 0


func _ready() -> void:
	# Voxel terrain streams in; wait for the spawn area before dropping anything onto it.
	await VoxelWorld.add_and_wait(self, WORLD)
	# Equipped the way the game does it: one rifle, held by the body, seen in first person.
	add_child((load(MODULE) as GDScript).new())
	_player = (load(PLAYER) as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3(0.0, 0.1, 0.0)
	EventBus.publish(&"player.spawned", {"player": _player, "local": true})
	var animator := PlayerBodyAnimator.new()
	animator.player = _player
	_player.add_child(animator)
	PlayerBody.first_person(_player.get_node("Body"))
	(_player.get_node("Head/Camera") as Camera3D).current = true
	var dummy: Node3D = (load(DUMMY) as PackedScene).instantiate()
	add_child(dummy)
	dummy.global_position = Vector3(0.0, 0.0, -8.0)


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	_ticks += 1
	# Bursts lined up with the capture frames (every 25 ticks for 150 frames / 6), so the
	# sampled frames land mid-burst and show tracers and hit markers; the pauses between
	# bursts show recoil recovery.
	_player.intent().fire = _ticks > 20 and (_ticks % 25) < 6 or (_ticks % 25) > 21

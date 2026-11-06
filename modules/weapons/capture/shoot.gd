extends Node3D
## Capture setup: first-person view firing bursts at a training dummy until it falls,
## with the HUD (crosshair, hit marker, ammo) and tracers visible.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const RIFLE := "res://modules/weapons/scenes/rifle.tscn"
const DUMMY := "res://modules/training/scenes/dummy.tscn"

var _player: PlayerController
var _ticks := 0


func _ready() -> void:
	add_child((load(WORLD) as PackedScene).instantiate())
	_player = (load(PLAYER) as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3(0.0, 0.1, 0.0)
	(_player.get_node("BodyMesh") as MeshInstance3D).visible = false
	var camera: Camera3D = _player.get_node("Head/Camera")
	camera.current = true
	var rifle: HitscanWeapon = (load(RIFLE) as PackedScene).instantiate()
	rifle.holder = _player
	camera.add_child(rifle)
	var dummy: Node3D = (load(DUMMY) as PackedScene).instantiate()
	add_child(dummy)
	dummy.global_position = Vector3(0.0, 0.0, -8.0)
	var feedback := ShotFeedback.new()
	feedback.local_player = _player
	add_child(feedback)


func _physics_process(_delta: float) -> void:
	_ticks += 1
	# Bursts lined up with the capture frames (every 25 ticks for 150 frames / 6), so the
	# sampled frames land mid-burst and show tracers and hit markers; the pauses between
	# bursts show recoil recovery.
	_player.intent().fire = _ticks > 20 and (_ticks % 25) < 6 or (_ticks % 25) > 21

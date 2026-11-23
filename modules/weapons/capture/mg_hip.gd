extends Node3D
## Capture setup: first person with the machine gun at a dummy 20 m off. A long burst from
## the hip standing (tracers scatter wide), then crouched on the bipod (they bunch up), then
## aimed down the iron sights for a last burst.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const DUMMY := "res://modules/training/scenes/dummy.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"

var _player: PlayerController
var _ticks := 0


func _ready() -> void:
	GunAssembly.override_build = "mg_standard"
	var world := await VoxelWorld.add_and_wait(self, WORLD)
	add_child((load(MODULE) as GDScript).new())
	_player = (load(PLAYER) as PackedScene).instantiate()
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
	dummy.global_position = VoxelWorld.spawn_of(world, Vector3(0.0, 0.0, -20.0))


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	_ticks += 1
	var intent := _player.intent()
	# Physics ticks, two to each captured frame.
	intent.crouch = _ticks > 180
	intent.aim = _ticks > 340
	intent.fire = (_ticks > 60 and _ticks < 140) or (_ticks > 220 and _ticks < 300) or (_ticks > 400 and _ticks < 480)

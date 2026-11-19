extends Node3D
## Capture setup: three soldiers stand side by side in front of the camera and are killed one
## after another, each shot from a different side, and fall as ragdolls (#130).

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
## [x offset on the line, physics tick it dies on, push direction]: left one to the left,
## middle one away from the camera, right one towards it.
const VICTIMS := [
	[-2.5, 20, Vector3(-1.0, 0.0, 0.0)],
	[0.0, 60, Vector3(0.0, 0.0, -1.0)],
	[2.5, 100, Vector3(0.0, 0.0, 1.0)],
]
const CAMERA_AT := Vector3(0.0, 1.9, 5.0)
## Ticks for the soldiers to land; then they hold still (the road slopes, and nobody steers).
const LANDED := 12

var _soldiers: Array[PlayerController] = []
var _camera := Camera3D.new()
var _ticks := 0


func _ready() -> void:
	await VoxelWorld.add_and_wait(self, WORLD)
	Corpse.enabled = true
	for v: Array in VICTIMS:
		var soldier: PlayerController = (load(PLAYER) as PackedScene).instantiate()
		add_child(soldier)
		soldier.global_position = Vector3(float(v[0]), 0.5, 0.0)
		var animator := PlayerBodyAnimator.new()
		animator.name = "BodyAnimator"
		animator.player = soldier
		soldier.add_child(animator)
		_soldiers.append(soldier)
	add_child(_camera)
	_camera.current = true
	_camera.global_position = CAMERA_AT
	_camera.look_at(Vector3(0.0, 0.8, 0.0))


func _physics_process(_delta: float) -> void:
	if _soldiers.is_empty():
		return
	_ticks += 1
	if _ticks == LANDED:
		for soldier in _soldiers:
			soldier.set_physics_process(false)
	for i in VICTIMS.size():
		var v: Array = VICTIMS[i]
		if _ticks == int(v[1]):
			var soldier := _soldiers[i]
			var push := (v[2] as Vector3) * float(Corpse.config()["push"]) + Vector3.UP * float(Corpse.config()["push_up"])
			Corpse.from_body(soldier, push)
			(soldier.get_node("Body") as Node3D).visible = false
			soldier.set_physics_process(false)

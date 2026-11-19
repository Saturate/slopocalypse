extends Node3D
## Capture setup: three soldiers are shot dead one after another, fall as ragdolls, and once
## each has settled a pool of blood spreads under its chest (#385). Run it for about 12 s
## (360 frames): bodies settle after 4 s and pools take 6 s to spread.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
## [x on the line, physics tick it dies on, which way it is shot (and falls)].
const VICTIMS := [
	[-2.2, 20, Vector3(-1.0, 0.0, 0.0)],
	[0.0, 40, Vector3(0.0, 0.0, -1.0)],
	[2.2, 60, Vector3(0.3, 0.0, -1.0)],
]
const LANDED := 12

var _soldiers: Array[PlayerController] = []
var _camera := Camera3D.new()
var _ticks := 0


func _ready() -> void:
	await VoxelWorld.add_and_wait(self, WORLD)
	Corpse.enabled = true
	for v: Array in VICTIMS:
		var soldier: PlayerController = (load(PLAYER) as PackedScene).instantiate()
		soldier.add_to_group(&"enemies")
		add_child(soldier)
		soldier.global_position = Vector3(float(v[0]), 0.5, 0.0)
		var animator := PlayerBodyAnimator.new()
		animator.name = "BodyAnimator"
		animator.player = soldier
		soldier.add_child(animator)
		_soldiers.append(soldier)
	add_child(BloodEffects.new())
	add_child(_camera)
	_camera.current = true
	_camera.global_position = Vector3(0.0, 3.6, 4.2)
	_camera.look_at(Vector3(0.0, 0.0, -0.4))


func _physics_process(_delta: float) -> void:
	if _soldiers.is_empty():
		return
	_ticks += 1
	if _ticks == LANDED:
		for soldier in _soldiers:
			soldier.set_physics_process(false)
	for i in VICTIMS.size():
		var v: Array = VICTIMS[i]
		if _ticks != int(v[1]):
			continue
		var soldier := _soldiers[i]
		var way := (v[2] as Vector3).normalized()
		var to := soldier.global_position + Vector3(0.0, 1.2, 0.0) - way * 0.3
		EventBus.publish(&"weapon.fired", {"from": to - way * 8.0, "to": to, "target": soldier, "collider": soldier, "damage": 100.0})
		var push := way * float(Corpse.config()["push"]) + Vector3.UP * float(Corpse.config()["push_up"])
		Corpse.from_body(soldier, push)
		(soldier.get_node("Body") as Node3D).visible = false
		(soldier.get_node("Shape") as CollisionShape3D).set_deferred(&"disabled", true)

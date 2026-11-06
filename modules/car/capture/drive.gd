extends Node3D
## Capture setup: the box car drives off the spawn pad, accelerates and turns across the
## world, seen from its own chase camera.

const WORLD := "res://modules/world/scenes/world.tscn"
const CAR := "res://modules/car/scenes/box_car.tscn"

var _car: CarController
var _driver := Node3D.new()
var _ticks := 0


func _ready() -> void:
	# Voxel terrain streams in; wait for the spawn area before dropping anything onto it.
	await VoxelWorld.add_and_wait(self, WORLD)
	_car = (load(CAR) as PackedScene).instantiate()
	add_child(_car)
	_car.global_position = Vector3(-4.0, 1.0, -8.0)
	add_child(_driver)
	_car.camera().current = true


func _physics_process(_delta: float) -> void:
	if _car == null:
		return
	_ticks += 1
	if _ticks == 30:
		_driver.global_position = _car.global_position
		_car.enter(_driver)
	var intent := _car.intent()
	intent.throttle = 1.0 if _ticks > 30 else 0.0
	intent.steer = 0.6 if _ticks > 100 and _ticks < 160 else 0.0

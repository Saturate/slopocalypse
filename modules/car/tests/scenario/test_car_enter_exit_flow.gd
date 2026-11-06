extends GdUnitTestSuite
## The real enter/exit flow through both modules and the event bus, driven by intents as in
## play. Regression test: pressing E is handled inside the player's own physics step, the car
## parks the player (body leaves the physics space), and the rest of that step used to call
## move_and_slide anyway ("Parameter space is null" from body_test_motion). The gate fails
## on that error line.

const PLAYER_MODULE := "res://modules/player/player_module.gd"
const CAR_MODULE := "res://modules/car/car_module.gd"

var _floor: StaticBody3D
var _players: Node
var _cars: Node


func before_test() -> void:
	_floor = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	_floor.add_child(shape)
	add_child(_floor)
	_players = (load(PLAYER_MODULE) as GDScript).new()
	add_child(_players)
	_cars = (load(CAR_MODULE) as GDScript).new()
	add_child(_cars)
	EventBus.publish(&"world.ready", {"spawn": Vector3(0, 1, 0), "kill_y": -40.0})


func after_test() -> void:
	_cars.free()
	_players.free()
	_floor.free()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func test_leaving_the_car_from_its_physics_step_keeps_the_player_in_the_world() -> void:
	var player: PlayerController = _players.get_node("LocalPlayer")
	var car: CarController = _cars.get_child(0)
	await _frames(30)
	player.global_position = car.global_position + Vector3(2.0, 0.5, 0.0)
	await _frames(5)
	# Press E the way play does: the player's own physics step publishes the interact, and
	# the car parks the player in the middle of that step.
	player.intent().interact = true
	await _frames(2)
	assert_object(car.driver).is_same(player)
	await _frames(30)
	# Exit the way play does it: the car reads the intent in its own physics step.
	car.intent().exit = true
	await _frames(30)
	assert_object(car.driver).is_null()
	assert_bool(player.is_on_floor()).is_true()

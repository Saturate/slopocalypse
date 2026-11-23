extends GdUnitTestSuite
## A car driving into someone shoves them out of the way instead of stopping dead against
## them, and hurts them above a speed.

const CAR := "res://modules/car/scenes/box_car.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"

var _ground: StaticBody3D
var _car: CarController
var _driver: Node3D


func before_test() -> void:
	_ground = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	_ground.add_child(shape)
	add_child(_ground)
	_car = (load(CAR) as PackedScene).instantiate()
	_car.add_to_group(&"vehicles")
	add_child(_car)
	_car.global_position = Vector3(0.0, 1.0, 0.0)
	_driver = auto_free(Node3D.new())
	add_child(_driver)


func after_test() -> void:
	_car.free()
	_ground.free()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## Someone standing still `metres` ahead of the car's nose (+Z).
func _stander(metres: float) -> PlayerController:
	var person: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	person.add_to_group(&"players")
	add_child(person)
	person.global_position = Vector3(0.0, 0.1, metres)
	return person


func _drive_into(person: PlayerController, throttle: float, frames: int) -> float:
	await _frames(60)
	_driver.global_position = _car.global_position
	_car.enter(_driver)
	_car.intent().throttle = throttle
	var health := person.get_node("Health") as HealthComponent
	var before := health.health
	await _frames(frames)
	return before - health.health


func test_a_car_shoves_someone_aside_and_keeps_going() -> void:
	var person := _stander(8.0)
	await _drive_into(person, 0.5, 240)
	# Past where they stood, still moving, and they are out of its way.
	assert_float(_car.global_position.z).is_greater(12.0)
	assert_float(_car.forward_speed()).is_greater(2.0)
	assert_float(person.global_position.distance_to(Vector3(0.0, 0.1, 8.0))).is_greater(1.5)


func test_someone_killed_by_a_car_is_not_thrown_again_when_they_come_back() -> void:
	var person := _stander(30.0)
	person.add_to_group(&"enemies")
	person.remove_from_group(&"players")
	var health := person.get_node("Health") as HealthComponent
	health.max_health = 1.0
	health.server_reset()
	# As the player module marks the dead, the moment they die.
	health.died.connect(func(_source: Node) -> void: person.set_meta(&"dead", true))
	await _drive_into(person, 1.0, 300)
	assert_bool(health.is_dead()).is_true()
	# Back at a respawn: nothing left over from the hit carries them off.
	person.set_meta(&"dead", false)
	health.server_reset()
	var back_at := Vector3(-50.0, 0.1, -50.0)
	person.global_position = back_at
	await _frames(60)
	assert_float(Vector2(person.global_position.x - back_at.x, person.global_position.z - back_at.z).length()).is_less(0.5)


func test_someone_pinned_against_a_wall_never_ends_up_inside_the_car() -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 4.0, 0.5)
	shape.shape = box
	wall.add_child(shape)
	add_child(auto_free(wall))
	wall.global_position = Vector3(0.0, 2.0, 12.0)
	var person := _stander(11.0)
	await _drive_into(person, 0.4, 360)
	_car.intent().throttle = 0.0
	await _frames(120)
	# Out of the car's body by now, to one side.
	var inside: Array = _car.call(&"_people_in", 0.0)
	assert_bool(inside.has(person)).is_false()


func test_a_fast_car_hurts_who_it_hits_and_a_slow_one_does_not() -> void:
	var slow := _stander(6.0)
	slow.add_to_group(&"enemies")
	var hurt := await _drive_into(slow, 0.15, 240)
	assert_float(hurt).is_equal(0.0)
	_car.intent().throttle = 0.0
	_car.free()
	_car = (load(CAR) as PackedScene).instantiate()
	_car.add_to_group(&"vehicles")
	add_child(_car)
	_car.global_position = Vector3(20.0, 1.0, 0.0)
	var fast := _stander(60.0)
	fast.add_to_group(&"enemies")
	fast.global_position.x = 20.0
	hurt = await _drive_into(fast, 1.0, 360)
	assert_float(hurt).is_greater(10.0)

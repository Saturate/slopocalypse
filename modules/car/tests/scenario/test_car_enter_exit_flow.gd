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
	var player: PlayerController = _players.players()[0]
	var car: CarController = _cars.cars()[0]
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


func _drive(player: PlayerController, car: CarController) -> void:
	await _frames(30)
	player.global_position = car.global_position + Vector3(2.0, 0.5, 0.0)
	await _frames(5)
	player.intent().interact = true
	await _frames(2)
	assert_object(car.driver).is_same(player)


## Nothing solid of a car's where a person would stand with their feet at `at`.
func _clear_of_cars(at: Vector3, exclude: RID) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = PlayerController.STAND_CHECK_RADIUS
	capsule.height = PlayerController.STAND_CHECK_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * (PlayerController.STAND_CHECK_HEIGHT / 2.0 + 0.05))
	query.exclude = [exclude]
	for hit: Dictionary in get_viewport().find_world_3d().direct_space_state.intersect_shape(query, 8):
		var body := hit["collider"] as Node
		if body != null and body.is_in_group(&"vehicles"):
			return false
	return true


func test_a_driver_is_saved_where_they_would_get_out() -> void:
	var player: PlayerController = _players.players()[0]
	var car: CarController = _cars.cars()[0]
	await _drive(player, car)
	var parked := player.global_position
	var spot: Variant = _cars.call(&"exit_spot_of", player)
	assert_bool(spot is Vector3).is_true()
	assert_vector(spot as Vector3).is_equal_approx(car.exit_position(), Vector3.ONE * 0.01)
	# Asking moves nobody.
	assert_object(car.driver).is_same(player)
	assert_vector(player.global_position).is_equal(parked)


func test_a_driver_who_leaves_the_server_is_let_out_first() -> void:
	var player: PlayerController = _players.players()[0]
	var car: CarController = _cars.cars()[0]
	await _drive(player, car)
	Net.peer_leaving.emit(int(player.get_meta(&"peer_id")))
	await _frames(2)
	# Out of the seat and standing at the door, so the spot saved for them is not in the car.
	assert_object(car.driver).is_null()
	assert_bool(_clear_of_cars(player.global_position, player.get_rid())).is_true()


func test_a_new_player_does_not_spawn_inside_a_parked_car() -> void:
	var car: CarController = _cars.cars()[0]
	await _frames(30)
	# Parked right on the spawn.
	car.global_position = Vector3(0.0, 1.0, 0.0)
	await _frames(10)
	_players.call(&"_server_spawn", 4242)
	await _frames(2)
	var joined: PlayerController = null
	for p: PlayerController in _players.players():
		if int(p.get_meta(&"peer_id", 0)) == 4242:
			joined = p
	assert_object(joined).is_not_null()
	assert_bool(_clear_of_cars(joined.global_position, joined.get_rid())).is_true()


func test_both_seats_count_where_the_car_is_and_getting_out_ends_it() -> void:
	var driver: PlayerController = _players.players()[0]
	var car: CarController = _cars.cars()[0]
	await _drive(driver, car)
	var passenger := Node3D.new()
	add_child(auto_free(passenger))
	passenger.global_position = car.global_position + Vector3(1.0, 0.0, 0.0)
	car.enter(passenger)
	assert_object(car.passenger).is_same(passenger)
	# Driven off: the driver's body stays parked where they got in, the answer follows the car.
	car.global_position += Vector3(30.0, 0.0, 0.0)
	for who: Node3D in [driver, passenger]:
		var spot: Variant = _cars.call(&"car_spot_of", who)
		assert_bool(spot is Vector3).is_true()
		assert_vector(spot as Vector3).is_equal_approx(car.global_position, Vector3.ONE * 0.01)
	assert_vector(PlayerSpot.of(driver, _cars)).is_equal_approx(car.global_position, Vector3.ONE * 0.01)
	car.exit_car(passenger)
	car.exit_car(driver)
	await _frames(2)
	assert_object(_cars.call(&"car_spot_of", driver)).is_null()
	assert_object(_cars.call(&"car_spot_of", passenger)).is_null()
	assert_vector(PlayerSpot.of(driver, _cars)).is_equal(driver.global_position)

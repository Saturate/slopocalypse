extends GdUnitTestSuite
## Someone who joins while a car is occupied (#433): the server lists the taken seats, and
## the joiner's side replays each as the `car.entered` it missed, once the car and the player
## in it have both appeared there.

const PLAYER_MODULE := "res://modules/player/player_module.gd"
const CAR_MODULE := "res://modules/car/car_module.gd"
## A peer id no test player has, for someone whose player appears later.
const LATE_PEER := 77

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


func _solid(player: PlayerController) -> bool:
	return not (player.get_node("Shape") as CollisionShape3D).disabled


func test_the_server_lists_who_sits_where() -> void:
	var player: PlayerController = _players.players()[0]
	var car: CarController = _cars.cars()[0]
	assert_array(_cars.occupied_seats()).is_empty()
	car.enter(player)
	var seats: Array[Dictionary] = _cars.occupied_seats()
	assert_int(seats.size()).is_equal(1)
	assert_str(str(seats[0]["car"])).is_equal(str(car.get_path()))
	assert_str(str(seats[0]["player"])).is_equal(str(player.get_path()))
	assert_str(str(seats[0]["seat"])).is_equal(str(CarController.DRIVER))
	car.exit_car(player)
	assert_array(_cars.occupied_seats()).is_empty()


func test_a_joiner_sees_the_driver_parked_and_the_car_taken() -> void:
	var player: PlayerController = _players.players()[0]
	var car: CarController = _cars.cars()[0]
	await _frames(5)
	# What the server sends a joiner, with nobody having got in on this side.
	_cars.catch_up_seat(car.get_path(), CarController.DRIVER, player.get_path())
	await _frames(2)
	assert_object(car.driver).is_same(player)
	assert_bool(player.visible).is_false()
	assert_bool(_solid(player)).is_false()


func test_a_seat_waits_for_its_player_to_appear() -> void:
	var first: PlayerController = _players.players()[0]
	var car: CarController = _cars.cars()[0]
	var late_path := NodePath("%s/%d" % [first.get_parent().get_path(), LATE_PEER])
	_cars.catch_up_seat(car.get_path(), CarController.PASSENGER, late_path)
	await _frames(3)
	assert_object(car.passenger).is_null()
	_players.call(&"_server_spawn", LATE_PEER)
	await _frames(3)
	var late := get_node(late_path) as PlayerController
	assert_object(car.passenger).is_same(late)
	assert_bool(late.visible).is_false()
	assert_bool(_solid(late)).is_false()
	# The player already here was not touched.
	assert_bool(first.visible).is_true()


func test_someone_who_got_out_before_appearing_is_not_parked() -> void:
	var first: PlayerController = _players.players()[0]
	var car: CarController = _cars.cars()[0]
	var late_path := NodePath("%s/%d" % [first.get_parent().get_path(), LATE_PEER])
	_cars.catch_up_seat(car.get_path(), CarController.DRIVER, late_path)
	# The replayed exit names a player this side cannot find yet.
	EventBus.publish(&"car.exited", {"player": null, "car": car, "seat": CarController.DRIVER, "position": Vector3.ZERO})
	_players.call(&"_server_spawn", LATE_PEER)
	await _frames(3)
	var late := get_node(late_path) as PlayerController
	assert_object(car.driver).is_null()
	assert_bool(late.visible).is_true()
	assert_bool(_solid(late)).is_true()

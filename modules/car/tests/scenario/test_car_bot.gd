extends GdUnitTestSuite
## The drive bot the net smoke runs (`--bot=drive`) must get in and drive the car 5 m, through
## the real player and car modules, even when the car cannot move at first (#581). On the map
## the players start behind the car.

const PLAYER_MODULE := "res://modules/player/player_module.gd"
const CAR_MODULE := "res://modules/car/car_module.gd"
const SPAWN := Vector3(0, 1, 0)
## Where the map's camp puts the car from the spawn, nose along +Z, away from the players.
const CAR_OFFSET := Vector3(-2, 0, 6)

var _floor: StaticBody3D
var _players: Node
var _cars: Node


func before_test() -> void:
	_floor = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	_floor.add_child(shape)
	add_child(_floor)
	_players = (load(PLAYER_MODULE) as GDScript).new()
	add_child(_players)
	_cars = (load(CAR_MODULE) as GDScript).new()
	add_child(_cars)
	EventBus.publish(&"world.ready", {"spawn": SPAWN, "car": Transform3D(Basis.IDENTITY, SPAWN + CAR_OFFSET), "kill_y": -40.0})


func after_test() -> void:
	_cars.free()
	_players.free()
	_floor.free()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _start_bot(player: PlayerController) -> void:
	var bot := CarBot.new()
	bot.name = "Bot"
	bot.player = player
	_cars.set(&"_bot", bot)
	_cars.add_child(bot)


func _drives_from(offset_from_car: Vector3) -> void:
	var player: PlayerController = _players.players()[0]
	var car: CarController = _cars.cars()[0]
	await _frames(30)
	player.global_position = car.global_position + offset_from_car + Vector3.UP * 0.5
	var start := car.global_position
	_start_bot(player)
	var got_in := false
	for i in 900:
		await get_tree().physics_frame
		got_in = got_in or car.driver == player
		if got_in and car.global_position.distance_to(start) >= 5.0:
			break
	assert_bool(got_in).override_failure_message("the bot never got in").is_true()
	assert_float(car.global_position.distance_to(start)).is_greater_equal(5.0)


func test_the_bot_gets_in_from_the_spawn() -> void:
	await _drives_from(-CAR_OFFSET)


# The car may not move at once (no ground under it yet, the throttle reaching the server
# late): the bot keeps driving until the car has gone somewhere, instead of for a fixed time.
func test_the_bot_drives_on_until_the_car_has_moved() -> void:
	var player: PlayerController = _players.players()[0]
	var car: CarController = _cars.cars()[0]
	await _frames(30)
	player.global_position = car.global_position + Vector3(3, 0.5, 0)
	var start := car.global_position
	_start_bot(player)
	for i in 600:
		await get_tree().physics_frame
		if car.driver == player:
			break
	assert_object(car.driver).is_same(player)
	# Held where it is for longer than a fixed drive used to last.
	for i in 300:
		car.freeze = true
		await get_tree().physics_frame
	car.freeze = false
	for i in 600:
		await get_tree().physics_frame
		if car.driver == null:
			break
	assert_float(car.global_position.distance_to(start)).is_greater_equal(5.0)

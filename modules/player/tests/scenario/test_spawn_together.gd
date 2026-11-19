extends GdUnitTestSuite
## Players who join in the same server tick must not share the spawn point: two bodies
## in one spot push each other out in the same direction every tick and slide off together
## at tens of metres a second (the net smoke's drive bot ended up 20 m away, on a hill).

const MODULE := "res://modules/player/player_module.gd"
const SPAWN := Vector3(0, 1, 0)

var _module: Node
var _floor: StaticBody3D


func before_test() -> void:
	_floor = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	_floor.add_child(shape)
	_floor.position = Vector3(0, -0.5, 0)
	add_child(_floor)
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)


func _players() -> Array[PlayerController]:
	var out: Array[PlayerController] = []
	out.assign(_module.call(&"players"))
	return out


func test_players_joining_in_one_tick_get_their_own_spot_and_stay_near_the_spawn() -> void:
	# The world being ready spawns this instance's own player; two more arrive in the same tick.
	EventBus.publish(&"world.ready", {"spawn": SPAWN})
	_module.call(&"_server_spawn", 2)
	_module.call(&"_server_spawn", 3)
	var players := _players()
	assert_int(players.size()).is_equal(3)
	var radius := float(players[0].config["radius"])
	for i in players.size():
		for j in range(i + 1, players.size()):
			assert_float(players[i].global_position.distance_to(players[j].global_position)).is_greater(radius * 2.0)
	for i in 60:
		await get_tree().physics_frame
	for p in players:
		assert_float(Vector2(p.global_position.x - SPAWN.x, p.global_position.z - SPAWN.z).length()).is_less(4.0)


func test_a_lone_player_still_starts_on_the_spawn() -> void:
	EventBus.publish(&"world.ready", {"spawn": SPAWN})
	assert_vector(_players()[0].global_position).is_equal(SPAWN)


func test_spacing_never_lets_two_bodies_overlap() -> void:
	var tight := {"spawn_spacing": 0.1, "radius": 0.35, "spawn_min_gap": 0.1}
	assert_float(_module.call(&"spawn_spacing_from", tight)).is_equal_approx(0.8, 0.0001)
	var wide := {"spawn_spacing": 2.0, "radius": 0.35, "spawn_min_gap": 0.1}
	assert_float(_module.call(&"spawn_spacing_from", wide)).is_equal_approx(2.0, 0.0001)

extends GdUnitTestSuite
## The city fills buildings near players with civilians, never more than `max_alive`, and
## empties buildings no player is near.


class FakeEnemies:
	extends Node
	var spawned: Array[Node] = []

	func server_spawn_civilian(at: Vector3, _yaw: float, _refuges: Array) -> Node:
		var n := Node3D.new()
		n.position = at
		add_child(n)
		spawned.append(n)
		return n


var _api: FakeEnemies
var _people: CityCivilians


func before_test() -> void:
	_api = auto_free(FakeEnemies.new())
	_api.add_to_group(&"enemies_api")
	add_child(_api)
	var site: CitySite = auto_free(CitySite.new())
	var buildings: Array = []
	for i in 10:
		buildings.append({"door_out": Vector2(i * 50.0, 0.0), "doors": [Vector2(i * 50.0, 0.0)]})
	site.plan = {"buildings": buildings}
	_people = auto_free(CityCivilians.new())
	_people.config = {"per_building": [2, 2], "max_alive": 5, "spawn_distance": 60.0, "despawn_distance": 120.0, "refuge_distance": 40.0}
	_people.site = site
	add_child(_people)


func test_only_buildings_near_players_fill_and_never_past_the_cap() -> void:
	_people.server_update([Vector3(0, 0, 0)])
	# Doors at 0 and 50 m are within 60 m: two buildings of two each.
	assert_int(_people.alive()).is_equal(4)
	_people.server_update([Vector3(0, 0, 0), Vector3(100, 0, 0)])
	# Buildings at 100 and 150 m now too, but the cap is 5.
	assert_int(_people.alive()).is_equal(5)


func test_buildings_far_from_everyone_empty() -> void:
	_people.server_update([Vector3(0, 0, 0)])
	assert_int(_people.alive()).is_equal(4)
	_people.server_update([Vector3(400, 0, 0)])
	await get_tree().process_frame
	assert_int(_people.alive()).is_equal(0)

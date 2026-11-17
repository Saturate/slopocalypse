extends GdUnitTestSuite
## Once the city stands, its guards go up on their spots: window posts on a floor with room to
## stand, roof posts on the roof, the rest on the pavement; and a wiped-out garrison comes back
## only when nobody is near.


## Records guards instead of spawning soldiers.
class FakeEnemies extends Node:
	var calls: Array = []

	func _ready() -> void:
		add_to_group(&"enemies_api")

	func server_spawn_guard(at: Vector3, yaw: float, route: Array = []) -> Node:
		calls.append({"at": at, "yaw": yaw, "route": route})
		var g: Node3D = Node3D.new()
		add_child(g)
		g.global_position = at
		return g


var _fake: FakeEnemies
var _site: CitySite
var _garrison: CityGarrison


func before_test() -> void:
	_fake = auto_free(FakeEnemies.new())
	add_child(_fake)
	var cfg: Dictionary = Data.load_json("res://modules/city/data/city.json")
	_site = auto_free(CitySite.new())
	_site.config = cfg
	add_child(_site)
	_site.build_all()
	_garrison = auto_free(CityGarrison.new())
	_garrison.config = cfg["guards"]
	_garrison.site = _site
	add_child(_garrison)
	await get_tree().physics_frame
	await get_tree().physics_frame


func test_guards_go_up_once_the_city_stands() -> void:
	await get_tree().process_frame
	var g: Dictionary = _garrison.config
	var expected := int(g["window_posts"]) + int(g["corner_posts"]) + int(g["patrols"])
	assert_int(_fake.calls.size()).is_between(expected, expected + int(g["roof_posts"]))
	assert_int(_garrison.alive()).is_equal(_fake.calls.size())


func test_window_posts_stand_on_a_floor_with_room() -> void:
	await get_tree().process_frame
	var space := _site.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	for c: Dictionary in _fake.calls:
		var at: Vector3 = c["at"]
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 0.6, PhysicsLayers.SOLID))
		assert_bool(down.is_empty()).override_failure_message("no floor under a guard at %s" % at).is_false()
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 1.0)
		query.collision_mask = PhysicsLayers.SOLID
		assert_array(space.intersect_shape(query, 1)).override_failure_message("no room for a guard at %s" % at).is_empty()


func test_a_wiped_out_garrison_comes_back_only_with_nobody_near() -> void:
	await get_tree().process_frame
	var first := _fake.calls.size()
	for g in _garrison.guards:
		g.set_meta(&"dead", true)
	var player: Node3D = auto_free(Node3D.new())
	player.add_to_group(&"players")
	add_child(player)
	player.global_position = _site.global_position
	_garrison.config["refill_seconds"] = 0.1
	for i in 10:
		await get_tree().process_frame
	assert_int(_fake.calls.size()).is_equal(first)
	player.global_position = _site.global_position + Vector3(1000, 0, 0)
	for i in 20:
		await get_tree().process_frame
	assert_int(_fake.calls.size()).is_greater(first)

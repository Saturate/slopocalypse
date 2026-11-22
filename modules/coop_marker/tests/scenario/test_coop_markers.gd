extends GdUnitTestSuite
## The co-op markers in a scene (#447): one per other player, with name and distance; a wall
## between you and them keeps the marker full, a clear line of sight close by makes it faint;
## nothing while you are dead or with the setting off; a partner in a car is marked over it.

const CONFIG := "res://modules/coop_marker/data/coop_marker.json"

var _camera: Camera3D
var _me: Node3D
var _markers: CoopMarkers


func before_test() -> void:
	# Looking north (-Z) from eye height.
	_camera = auto_free(Camera3D.new())
	add_child(_camera)
	_camera.global_position = Vector3(0, 1.7, 0)
	_camera.current = true
	_me = _player(Vector3.ZERO, "Me")
	_markers = auto_free(CoopMarkers.new())
	_markers.config = Data.load_json(CONFIG)
	_markers.player = _me
	add_child(_markers)


func _player(at: Vector3, who: String) -> Node3D:
	var n: Node3D = auto_free(Node3D.new())
	add_child(n)
	n.global_position = at
	n.add_to_group(&"players")
	n.set_meta(&"player_name", who)
	return n


func after_test() -> void:
	Settings.set_value("coop_marker", true)


func _wall(at: Vector3) -> StaticBody3D:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 4, 0.4)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = at + Vector3.UP * 2.0
	return body


func _only() -> Dictionary:
	var items := _markers.items()
	assert_int(items.size()).is_equal(1)
	return items[0] if items.size() == 1 else {}


func test_each_other_player_gets_one_with_name_and_distance() -> void:
	_player(Vector3(0, 0, -20), "Ana")
	var enemy := _player(Vector3(3, 0, -20), "")
	enemy.add_to_group(&"enemies")
	var item := _only()
	assert_str(str(item["name"])).is_equal("Ana")
	assert_int(int(item["metres"])).is_equal(CoopMarkerRules.metres(_camera.global_position.distance_to(Vector3(0, 0, -20))))
	assert_bool(bool(item["ahead"])).is_true()


func test_a_wall_keeps_it_full_and_a_clear_view_makes_it_faint() -> void:
	var config := Data.load_json(CONFIG) as Dictionary
	var close := float(config["in_view_m"]) * 0.5
	_player(Vector3(0, 0, -close), "Ana")
	await get_tree().physics_frame
	var clear := _only()
	assert_bool(bool(clear["in_sight"])).is_true()
	assert_float(float(clear["alpha"])).is_equal_approx(float(config["in_view_alpha"]), 0.0001)
	_wall(Vector3(0, 0, -close * 0.5))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var walled := _only()
	assert_bool(bool(walled["in_sight"])).is_false()
	assert_float(float(walled["alpha"])).is_equal(1.0)


func test_out_of_range_players_are_left_out() -> void:
	var config := Data.load_json(CONFIG) as Dictionary
	_player(Vector3(0, 0, -float(config["range_m"]) - 10.0), "Far")
	assert_array(_markers.items()).is_empty()


func test_nothing_while_you_are_dead() -> void:
	_player(Vector3(0, 0, -20), "Ana")
	_me.set_meta(&"dead", true)
	assert_array(_markers.items()).is_empty()


func test_a_partner_in_a_car_is_marked_over_the_car_which_does_not_hide_them() -> void:
	var config := Data.load_json(CONFIG) as Dictionary
	var ana := _player(Vector3(0, 0, -10), "Ana")
	ana.visible = false
	assert_array(_markers.items()).override_failure_message("parked hidden, not in a car: no marker").is_empty()
	var car := _wall(Vector3(0, 0, -float(config["in_view_m"]) * 0.5))
	_markers.rides[ana.get_instance_id()] = car
	await get_tree().physics_frame
	await get_tree().physics_frame
	var item := _only()
	assert_float(float(item["distance"])).is_equal_approx(_camera.global_position.distance_to(car.global_position), 0.01)
	assert_bool(bool(item["in_sight"])).override_failure_message("their own car must not block the view of them").is_true()


func test_the_setting_turns_them_off_and_the_fade_forgets_whoever_left() -> void:
	var ana := _player(Vector3(0, 0, -60), "Ana")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_dict(_markers._shown).contains_keys([ana.get_instance_id()])
	Settings.set_value("coop_marker", false)
	await get_tree().process_frame
	assert_bool(_markers.visible).is_false()
	assert_dict(_markers._shown).is_empty()

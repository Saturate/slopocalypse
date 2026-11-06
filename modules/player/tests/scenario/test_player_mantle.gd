extends GdUnitTestSuite
## Mantling: Space next to a ledge climbs onto it; in the open it is only a small hop.
## Flat test ground and boxes placed in front of the player (-Z) keep it deterministic.

const PLAYER := "res://modules/player/scenes/player.tscn"

var _player: PlayerController
var _props: Array[Node] = []


func before_test() -> void:
	_box(Vector3(200.0, 1.0, 200.0), Vector3(0.0, -0.5, 0.0))
	_player = (load(PLAYER) as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3(0.0, 0.1, 0.0)


func after_test() -> void:
	_player.free()
	for p in _props:
		p.free()
	_props.clear()


func _box(size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = center
	_props.append(body)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## A crate of the given height whose near face is `gap` metres in front of the player.
func _crate(height: float, gap: float = 0.3) -> void:
	_box(Vector3(2.0, height, 2.0), Vector3(0.0, height / 2.0, -(0.35 + gap + 1.0)))


func test_climbs_onto_a_chest_high_crate() -> void:
	_crate(1.2)
	await _frames(20)
	_player.intent().jump = true
	await _frames(40)
	assert_bool(_player.is_mantling()).is_false()
	assert_float(_player.global_position.y).is_equal_approx(1.2, 0.15)
	# Ends up over the crate, not still in front of it.
	assert_float(_player.global_position.z).is_less(-0.6)


func test_wall_too_tall_is_not_climbed() -> void:
	_crate(3.0)
	await _frames(20)
	_player.intent().jump = true
	await _frames(60)
	assert_float(_player.global_position.y).is_less(0.2)


func test_no_room_on_top_means_no_mantle() -> void:
	_crate(1.0)
	# A ceiling just above the crate top leaves no space to stand.
	_box(Vector3(2.0, 0.4, 2.0), Vector3(0.0, 1.0 + 1.0 + 0.2, -(0.35 + 0.3 + 1.0)))
	await _frames(20)
	_player.intent().jump = true
	await _frames(60)
	assert_float(_player.global_position.y).is_less(0.2)


func test_open_ground_is_only_a_small_hop() -> void:
	await _frames(20)
	_player.intent().jump = true
	var peak := 0.0
	for i in 60:
		await get_tree().physics_frame
		peak = maxf(peak, _player.global_position.y)
	assert_float(peak).is_greater(0.2)
	assert_float(peak).is_less(0.7)
	assert_bool(_player.is_on_floor()).is_true()

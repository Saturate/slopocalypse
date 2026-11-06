extends GdUnitTestSuite
## Sprint momentum, vaulting low cover and sliding, on flat test ground.

const PLAYER := "res://modules/player/scenes/player.tscn"

var _player: PlayerController
var _props: Array[Node] = []


func before_test() -> void:
	_box(Vector3(400.0, 1.0, 400.0), Vector3(0.0, -0.5, 0.0))
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


func _sprint_forward() -> void:
	_player.intent().move = Vector2(0.0, 1.0)
	_player.intent().sprint = true


func test_sprint_builds_up_instead_of_snapping() -> void:
	await _frames(10)
	_sprint_forward()
	await _frames(20)
	var early := _player.horizontal_speed()
	await _frames(60)
	var sprint: float = _player.config["sprint_speed"]
	assert_float(early).is_less(sprint - 1.0)
	assert_float(_player.horizontal_speed()).is_equal_approx(sprint, sprint * 0.1)


func test_firing_drops_out_of_sprint() -> void:
	await _frames(10)
	_sprint_forward()
	_player.intent().fire = true
	await _frames(90)
	var walk: float = _player.config["walk_speed"]
	assert_float(_player.horizontal_speed()).is_equal_approx(walk, walk * 0.1)


func test_sprinting_vaults_over_low_thin_cover() -> void:
	# Waist-high wall, 0.4 m thick, 6 m ahead.
	_box(Vector3(4.0, 0.9, 0.4), Vector3(0.0, 0.45, -6.0))
	await _frames(10)
	_sprint_forward()
	# Jump once the wall is in reach.
	for i in 240:
		await get_tree().physics_frame
		# Within arm's reach of the wall face (radius + mantle_reach = 1.05 m).
		if _player.global_position.z < -5.0 and not _player.is_vaulting():
			_player.intent().jump = true
			break
	await _frames(40)
	assert_float(_player.global_position.z).is_less(-6.5)
	assert_float(_player.global_position.y).is_less(0.3)
	# Momentum carries through the vault.
	assert_float(_player.horizontal_speed()).is_greater(4.0)


func test_thick_cover_is_mantled_not_vaulted() -> void:
	_box(Vector3(4.0, 0.9, 3.0), Vector3(0.0, 0.45, -6.0))
	await _frames(10)
	_sprint_forward()
	var vaulted := false
	for i in 240:
		await get_tree().physics_frame
		if _player.global_position.z < -3.6 and not _player.is_mantling() and not _player.is_vaulting():
			_player.intent().jump = true
			await get_tree().physics_frame
			vaulted = _player.is_vaulting()
			break
	_player.intent().move = Vector2.ZERO
	await _frames(40)
	assert_bool(vaulted).is_false()
	assert_float(_player.global_position.y).is_equal_approx(0.9, 0.15)


func test_crouch_while_sprinting_slides_then_slows() -> void:
	await _frames(10)
	_sprint_forward()
	await _frames(120)
	var before := _player.horizontal_speed()
	_player.intent().crouch = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(_player.is_sliding()).is_true()
	assert_float(_player.horizontal_speed()).is_greater(before)
	await _frames(90)
	assert_bool(_player.is_sliding()).is_false()
	var crouch: float = _player.config["crouch_speed"]
	assert_float(_player.horizontal_speed()).is_less(crouch + 0.5)

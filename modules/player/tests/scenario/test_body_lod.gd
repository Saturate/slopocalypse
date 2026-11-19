extends GdUnitTestSuite
## Someone else's body on a client is posed every frame up close and in view, less often far
## off or out of view, and still holds its gun when it is; your own is posed every frame.

const PLAYER := "res://modules/player/scenes/player.tscn"
const WEAPONS := "res://modules/weapons/weapons_module.gd"
const FRAMES := 40

var _camera: Camera3D
var _weapons: Node
var _peer := 300


func before_test() -> void:
	_camera = auto_free(Camera3D.new())
	_camera.fov = 80.0
	add_child(_camera)
	_camera.global_position = Vector3(0.0, 1.6, 0.0)
	_camera.make_current()
	_weapons = auto_free((load(WEAPONS) as GDScript).new())
	add_child(_weapons)


func _copy(at: Vector3, lod: bool) -> PlayerBodyAnimator:
	_peer += 1
	var copy: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	copy.set_meta(&"peer_id", _peer)
	copy.add_to_group(&"players")
	copy.position = at
	PlayerController.hold_still(copy)
	add_child(copy)
	# Its own camera must not take over the view.
	_camera.make_current()
	EventBus.publish(&"player.spawned", {"player": copy, "local": false})
	_weapons.call(&"server_set_build", _peer, GunAssembly.build("ar_standard"))
	var animator := PlayerBodyAnimator.new()
	animator.name = "BodyAnimator"
	animator.player = copy
	animator.lod = lod
	copy.add_child(animator)
	return animator


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## At least `count` frames and at least `seconds`, so a fast machine still sees slower poses.
func _frames_for(count: int, seconds: float) -> void:
	var until := Time.get_ticks_usec() + int(seconds * 1000000.0)
	var done := 0
	while done < count or Time.get_ticks_usec() < until:
		await get_tree().process_frame
		done += 1


func test_a_near_copy_in_view_is_posed_every_frame() -> void:
	var near := _copy(Vector3(0.0, 0.0, -6.0), true)
	await _frames(2)
	var start := near.poses
	await _frames(FRAMES)
	assert_int(near.poses - start).is_equal(FRAMES)


func test_a_far_copy_is_posed_less_often() -> void:
	var far := _copy(Vector3(0.0, 0.0, -90.0), true)
	await _frames(2)
	var start := far.poses
	var started := Time.get_ticks_usec()
	await _frames_for(FRAMES, 0.3)
	var seconds := float(Time.get_ticks_usec() - started) / 1000000.0
	var posed := far.poses - start
	assert_int(posed).is_greater(0)
	# At most one pose per far interval (plus two: where the window starts, and the shorter first wait).
	assert_int(posed).is_less_equal(int(seconds * BodyLod.shared().far_rate) + 2)
	assert_int(posed).is_less(FRAMES)


func test_a_copy_out_of_view_is_posed_less_often_even_up_close() -> void:
	var behind := _copy(Vector3(0.0, 0.0, 5.0), true)
	await _frames(2)
	var start := behind.poses
	var started := Time.get_ticks_usec()
	await _frames_for(FRAMES, 0.3)
	var seconds := float(Time.get_ticks_usec() - started) / 1000000.0
	var posed := behind.poses - start
	assert_int(posed).is_less_equal(int(seconds * BodyLod.shared().off_screen_rate) + 2)
	assert_int(posed).is_less(FRAMES)


func test_your_own_body_is_posed_every_frame_wherever_it_is() -> void:
	var own := _copy(Vector3(0.0, 0.0, 90.0), false)
	await _frames(2)
	var start := own.poses
	await _frames(FRAMES)
	assert_int(own.poses - start).is_equal(FRAMES)


func test_a_copy_posed_less_often_still_holds_its_gun() -> void:
	var mid := _copy(Vector3(0.0, 0.0, -25.0), true)
	await _frames(FRAMES)
	var player := mid.player
	var skeleton := player.get_node("Body/Skeleton") as Skeleton3D
	for side in ["R", "L"]:
		var hand := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Hand_" + side)).origin
		var marker := ShotEffects.held_rifle(player).find_child("Grip" + side, true, false) as Node3D
		assert_float(hand.distance_to(marker.global_position)).override_failure_message("%s hand is %.3f m off the grip" % [side, hand.distance_to(marker.global_position)]).is_less(0.03)

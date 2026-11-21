extends GdUnitTestSuite
## The held gun's sight covers the same share of the screen at any field of view (#376): a
## wider view (the FOV setting, the sprint widening) brings the gun nearer the eye instead of
## shrinking the sight picture, at the hip and aimed.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"
## Field-of-view settings checked against the default view.
const OFFSETS: Array[float] = [-10.0, 20.0]
## Share of the default sight picture's size the others may differ by.
const TOLERANCE := 0.03

var _module: Node


func before_test() -> void:
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)


func after_test() -> void:
	Settings.set_value("fov_offset", 0.0)


func _spawn(build: String) -> PlayerController:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", 31)
	player.add_to_group(&"players")
	add_child(player)
	EventBus.publish(&"player.spawned", {"player": player, "local": false})
	_module.call(&"server_set_build", 31, GunAssembly.build(build))
	# The pistol is the secondary: draw it.
	player.intent().weapon_2 = GunAssembly.weapon_slot_of(GunAssembly.build(build)) == "secondary"
	var animator := PlayerBodyAnimator.new()
	animator.name = "BodyAnimator"
	animator.player = player
	player.add_child(animator)
	var feel := PlayerCameraFeel.new()
	feel.name = "CameraFeel"
	feel.player = player
	feel.camera = player.get_node("Head/Camera")
	player.add_child(feel)
	PlayerBody.first_person(player.get_node("Body"))
	return player


## Where the sight sits on screen and how big it is there: x and y as a share of the half
## screen width, size as the screen share one metre of it covers. Size on screen goes with
## 1 / (distance * tan(fov / 2)).
func _sight_picture(player: PlayerController) -> Vector3:
	var camera := player.get_node("Head/Camera") as Camera3D
	var sight := ShotEffects.held_rifle(player).find_child("Sight", true, false) as Node3D
	var p := camera.global_transform.affine_inverse() * sight.global_position
	var half := -p.z * tan(deg_to_rad(camera.fov) * 0.5)
	return Vector3(p.x / half, p.y / half, 1.0 / half)


func _settle(player: PlayerController, aim: bool) -> Vector3:
	player.intent().aim = aim
	await get_tree().create_timer(0.5).timeout
	return _sight_picture(player)


func _expect_same(build: String, aim: bool) -> void:
	var player := _spawn(build)
	Settings.set_value("fov_offset", 0.0)
	var base := await _settle(player, aim)
	for offset in OFFSETS:
		Settings.set_value("fov_offset", offset)
		var seen := await _settle(player, aim)
		var what := "%s %s at FOV %+d" % [build, "aimed" if aim else "hip", int(offset)]
		assert_float(seen.z / base.z).override_failure_message("%s: sight is %.2fx its default size" % [what, seen.z / base.z]).is_between(1.0 - TOLERANCE, 1.0 + TOLERANCE)
		assert_float(absf(seen.x - base.x) + absf(seen.y - base.y)).override_failure_message("%s: sight moved on screen from %s to %s" % [what, base, seen]).is_less(TOLERANCE)
	player.queue_free()


func test_rifle_sight_keeps_its_size_aimed() -> void:
	await _expect_same("ar_standard", true)


func test_rifle_keeps_its_size_at_the_hip() -> void:
	await _expect_same("ar_standard", false)


func test_pistol_sight_keeps_its_size_aimed() -> void:
	await _expect_same("pistol_standard", true)


func test_pistol_keeps_its_size_at_the_hip() -> void:
	await _expect_same("pistol_standard", false)


func test_distance_scale_matches_the_view_width() -> void:
	assert_float(PlayerCameraFeel.distance_scale(80.0, 80.0)).is_equal_approx(1.0, 0.0001)
	# 100 degrees is tan(50) / tan(40) times as wide, so the gun comes that much nearer.
	assert_float(PlayerCameraFeel.distance_scale(80.0, 100.0)).is_equal_approx(tan(deg_to_rad(40.0)) / tan(deg_to_rad(50.0)), 0.0001)
	assert_float(PlayerCameraFeel.distance_scale(80.0, 70.0)).is_greater(1.0)

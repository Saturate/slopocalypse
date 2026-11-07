extends GdUnitTestSuite
## Each hand reaches the grip point the held gun names (its GripR / GripL markers), at the
## hip and aimed, whatever the handguard.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"
const REACH := 0.03

var _module: Node


func before_test() -> void:
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)


func _spawn(build: String) -> PlayerController:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", 21)
	player.add_to_group(&"players")
	add_child(player)
	EventBus.publish(&"player.spawned", {"player": player, "local": false})
	_module.call(&"server_set_build", 21, GunAssembly.build(build))
	var animator := PlayerBodyAnimator.new()
	animator.name = "BodyAnimator"
	animator.player = player
	player.add_child(animator)
	return player


func _gap(player: PlayerController, side: String) -> float:
	var skeleton := player.get_node("Body/Skeleton") as Skeleton3D
	var hand := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Hand_" + side)).origin
	var marker := ShotEffects.held_rifle(player).find_child("Grip" + side, true, false) as Node3D
	return hand.distance_to(marker.global_position)


func test_hands_hold_the_grip_and_the_handguard() -> void:
	for build: String in ["ar_standard", "ar_heavy", "ar_cqb"]:
		var player := _spawn(build)
		for i in 10:
			await get_tree().process_frame
		for side in ["R", "L"]:
			assert_float(_gap(player, side)).override_failure_message("%s %s hand is %.3f m off" % [build, side, _gap(player, side)]).is_less(REACH)
		player.queue_free()

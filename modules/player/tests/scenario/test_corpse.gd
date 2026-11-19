extends GdUnitTestSuite
## A dead body falls as a ragdoll copied from the living body: it drops onto the ground and
## stops moving, the living body is left as it was, and it pairs up with the LootBody where
## it fell, hiding that figure and going when the LootBody goes.

const PLAYER := "res://modules/player/scenes/player.tscn"

var _player: PlayerController


func before_test() -> void:
	Corpse.enabled = true
	var ground := auto_free(StaticBody3D.new()) as StaticBody3D
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	add_child(ground)
	_player = auto_free((load(PLAYER) as PackedScene).instantiate())
	_player.set_physics_process(false)
	add_child(_player)
	_player.global_position = Vector3(0.0, 0.0, 0.0)


func after_test() -> void:
	Corpse.enabled = DisplayServer.get_name() != "headless"
	for node in get_tree().get_nodes_in_group(Corpse.GROUP):
		node.free()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func test_a_corpse_falls_to_the_ground_and_settles() -> void:
	var corpse := Corpse.from_body(_player, Vector3(2.0, 1.0, 0.0))
	assert_object(corpse).is_not_null()
	var head := corpse.skeleton.find_bone("Head")
	var standing := (corpse.skeleton.global_transform * corpse.skeleton.get_bone_global_pose(head)).origin
	await _frames(int(Corpse.config()["settle_seconds"] * 60.0) + 10)
	assert_bool(corpse.is_settled()).is_true()
	var lying := (corpse.skeleton.global_transform * corpse.skeleton.get_bone_global_pose(head)).origin
	# The head was 1.6 m up; it ends near the ground, pushed along +X, and stays there.
	assert_float(lying.y).is_less(0.6)
	assert_float(lying.y).is_greater(-0.1)
	assert_float(lying.x).is_greater(standing.x)
	await _frames(30)
	var later := (corpse.skeleton.global_transform * corpse.skeleton.get_bone_global_pose(head)).origin
	assert_float(later.distance_to(lying)).is_less(0.01)


func test_a_pushed_corpse_falls_where_it_stood_and_does_not_slide_away() -> void:
	var push := Corpse.push_from(_player, null)
	var corpse := Corpse.from_body(_player, push)
	await _frames(int(Corpse.config()["settle_seconds"] * 60.0) + 10)
	var hips := corpse.skeleton.find_bone("Hips")
	var at := corpse.skeleton.global_transform * corpse.skeleton.get_bone_global_pose(hips).origin
	var moved := Vector2(at.x, at.z).length()
	print("corpse hips moved ", moved, " m")
	# Falling over puts the hips about a body's half-height from the feet; no more than that.
	assert_float(moved).is_less(1.2)


func test_the_living_body_is_left_alone() -> void:
	var corpse := Corpse.from_body(_player, Vector3.ZERO)
	await _frames(5)
	assert_object(_player.get_node_or_null("Body/AnimationTree")).is_not_null()
	assert_object(_player.get_node_or_null("Body/Skeleton/WeaponAttachment")).is_not_null()
	assert_object(corpse.get_node_or_null("PlayerBody/AnimationTree")).is_null()
	assert_int(corpse.simulator.get_child_count()).is_greater(10)


func test_it_stands_in_for_the_loot_body_where_it_fell_and_goes_with_it() -> void:
	var corpse := Corpse.from_body(_player, Vector3.ZERO)
	await _frames(2)
	var loot := LootBody.new()
	loot.position = Vector3(0.5, 0.0, 0.0)
	add_child(loot)
	assert_object(corpse.loot_body()).is_same(loot)
	for child in loot.get_children():
		if child is MeshInstance3D:
			assert_bool((child as MeshInstance3D).visible).is_false()
	loot.free()
	await _frames(1)
	assert_bool(is_instance_valid(corpse)).is_false()


func test_a_loot_body_already_there_is_found_by_the_corpse() -> void:
	var loot := auto_free(LootBody.new()) as LootBody
	add_child(loot)
	var corpse := Corpse.from_body(_player, Vector3.ZERO)
	await _frames(2)
	assert_object(corpse.loot_body()).is_same(loot)


func test_a_far_loot_body_is_not_taken() -> void:
	var corpse := Corpse.from_body(_player, Vector3.ZERO)
	await _frames(2)
	var loot := auto_free(LootBody.new()) as LootBody
	loot.position = Vector3(10.0, 0.0, 0.0)
	add_child(loot)
	await _frames(2)
	assert_object(corpse.loot_body()).is_null()

extends GdUnitTestSuite
## Limbs come off on clients (#387). A piece is cut from the body's own mesh by bone; a killing
## shot strong enough on an arm or leg, or a blast close by, takes limbs off the ragdoll: their
## bones collapse, a piece flies on the debris layer kept clear of blood, and it goes with the
## corpse. Weak shots, far blasts and blood turned off take nothing; at most `max_limbs` pieces
## lie about.

const PLAYER := "res://modules/player/scenes/player.tscn"
const BODY := "res://modules/player/scenes/player_body.tscn"

var _player: PlayerController
var _severing: LimbSevering


func before_test() -> void:
	Settings.reset()
	Corpse.enabled = true
	var ground := auto_free(StaticBody3D.new()) as StaticBody3D
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	ground.add_child(shape)
	add_child(ground)
	ground.global_position = Vector3(0.0, -0.5, 0.0)
	_player = _body(Vector3.ZERO)
	_severing = auto_free(LimbSevering.new())
	add_child(_severing)
	_severing.set_process(false)


func after_test() -> void:
	Settings.reset()
	Corpse.enabled = DisplayServer.get_name() != "headless"
	for node in get_tree().get_nodes_in_group(Corpse.GROUP):
		node.free()


func _body(at: Vector3) -> PlayerController:
	var body: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	body.set_physics_process(false)
	body.add_to_group(&"enemies")
	add_child(body)
	body.global_position = at
	return body


func _kill(body: PlayerController) -> Corpse:
	var corpse := Corpse.from_body(body, Vector3(0.0, 0.5, 1.0))
	(body.get_node("Body") as Node3D).visible = false
	(body.get_node("Shape") as CollisionShape3D).set_deferred(&"disabled", true)
	return corpse


func _bone_at(body: Node3D, bone_name: String) -> Vector3:
	var skeleton := body.get_node("Body/Skeleton") as Skeleton3D
	return (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name))).origin


func _shot(body: Node3D, at: Vector3, damage: float) -> void:
	EventBus.publish(&"weapon.fired", {"from": at + Vector3(0.0, 0.0, 6.0), "to": at, "target": body, "collider": body, "damage": damage})


func test_a_piece_is_cut_from_the_body_mesh_by_bone() -> void:
	var body := (load(BODY) as PackedScene).instantiate()
	var skeleton := body.get_node("Skeleton") as Skeleton3D
	var arms := body.get_node("Skeleton/Arms") as MeshInstance3D
	var legs := body.get_node("Skeleton/Mesh") as MeshInstance3D
	var forearm := LimbPieces.piece(arms, skeleton, "forearm_L")
	assert_object(forearm).is_not_null()
	# Laid out from the elbow: within an arm's length of its origin.
	var reach := forearm.get_aabb()
	assert_float(maxf(reach.position.length(), reach.end.length())).is_less(0.5)
	assert_object(LimbPieces.piece(arms, skeleton, "thigh_L")).is_null()
	assert_object(LimbPieces.piece(legs, skeleton, "thigh_L")).is_not_null()
	# Kept: the same piece every time.
	assert_object(LimbPieces.piece(arms, skeleton, "forearm_L")).is_same(forearm)
	body.free()


func test_a_strong_killing_shot_on_a_forearm_takes_it_off() -> void:
	var hand := _bone_at(_player, "LowerArm_L").lerp(_bone_at(_player, "Hand_L"), 0.5)
	var corpse := _kill(_player)
	_shot(_player, hand, 30.0)
	_severing.resolve(true)
	var pieces := _severing.pieces()
	assert_int(pieces.size()).is_equal(1)
	var piece := pieces[0]
	assert_int(piece.collision_layer).is_equal(PhysicsLayers.DEBRIS)
	assert_int(piece.collision_mask).is_equal(PhysicsLayers.SOLID | PhysicsLayers.GLASS)
	for mesh in piece.find_children("*", "GeometryInstance3D", true, false):
		assert_int((mesh as GeometryInstance3D).layers & RenderLayers.DEFAULT).is_equal(0)
	# The ragdoll's forearm is gone: collapsed, with no physics of its own.
	var skeleton := corpse.skeleton
	assert_float(skeleton.get_bone_pose_scale(skeleton.find_bone("LowerArm_L")).x).is_less(0.01)
	assert_float(skeleton.get_bone_pose_scale(skeleton.find_bone("UpperArm_L")).x).is_equal_approx(1.0, 0.001)
	assert_object(corpse.simulator.get_node_or_null("LowerArm_L")).is_null()
	# It goes with its corpse.
	corpse.free()
	assert_bool(is_instance_valid(piece)).is_false()


func test_weak_shots_and_body_shots_take_nothing() -> void:
	var hand := _bone_at(_player, "LowerArm_L").lerp(_bone_at(_player, "Hand_L"), 0.5)
	_kill(_player)
	_shot(_player, hand, 10.0)
	_severing.resolve(true)
	assert_int(_severing.pieces().size()).is_equal(0)
	var other := _body(Vector3(4.0, 0.0, 0.0))
	var chest := _bone_at(other, "Chest") + Vector3(0.0, 0.05, 0.0)
	_kill(other)
	_shot(other, chest, 100.0)
	_severing.resolve(true)
	assert_int(_severing.pieces().size()).is_equal(0)


func test_a_close_blast_takes_two_limbs_and_a_far_one_none() -> void:
	_kill(_player)
	EventBus.publish(&"explosion", {"position": Vector3(0.0, 0.3, 0.8), "radius": 3.0})
	_severing.resolve(true)
	assert_int(_severing.pieces().size()).is_equal(int(BloodEffects.config()["blast_max_limbs"]))
	var far := _body(Vector3(10.0, 0.0, 0.0))
	_kill(far)
	EventBus.publish(&"explosion", {"position": Vector3(10.0, 0.3, 0.0) + Vector3(0.0, 0.0, float(BloodEffects.config()["blast_sever_radius"]) + 1.0), "radius": 6.0})
	_severing.resolve(true)
	assert_int(_severing.pieces().size()).is_equal(int(BloodEffects.config()["blast_max_limbs"]))


func test_with_blood_off_nothing_comes_off() -> void:
	Settings.set_value("blood", false)
	_kill(_player)
	EventBus.publish(&"explosion", {"position": Vector3(0.0, 0.3, 0.5), "radius": 3.0})
	_severing.resolve(true)
	assert_int(_severing.pieces().size()).is_equal(0)


func test_at_most_max_limbs_pieces_lie_about() -> void:
	var cfg := BloodEffects.config()
	var cap := int(cfg["max_limbs"])
	for i in cap + 2:
		var body := _body(Vector3(float(i) * 3.0, 0.0, 0.0))
		var forearm := _bone_at(body, "LowerArm_R").lerp(_bone_at(body, "Hand_R"), 0.5)
		_kill(body)
		_shot(body, forearm, 100.0)
		_severing.resolve(true)
	assert_int(_severing.pieces().size()).is_equal(cap)


func test_a_severed_ragdoll_still_settles_cleanly() -> void:
	var corpse := _kill(_player)
	EventBus.publish(&"explosion", {"position": Vector3(0.0, 0.3, 0.8), "radius": 3.0})
	_severing.resolve(true)
	while not corpse.is_settled():
		await get_tree().physics_frame
	var skeleton := corpse.skeleton
	var gone := 0
	for limb: String in LimbRules.BLAST_LIMBS:
		if skeleton.get_bone_pose_scale(skeleton.find_bone(LimbRules.root_bone(limb))).x < 0.01:
			gone += 1
	assert_int(gone).is_equal(int(BloodEffects.config()["blast_max_limbs"]))

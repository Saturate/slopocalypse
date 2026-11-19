extends GdUnitTestSuite
## Limbs come off on clients (#387). A piece is cut from the body's own mesh by bone. A killing
## shot that dealt enough to a leg or (from the side) an arm, or a blast close by, takes limbs
## off the ragdoll: they lose their physics and collapse, a piece flies on the debris layer kept
## clear of blood, and it goes with the corpse. The death arrives first and the blow a frame
## later, as on a client. Weak shots, shots on someone else, blows outside the window, blasts
## that killed nobody, chest shots and blood turned off take nothing; at most `max_limbs` pieces
## lie about. Without its values in gore.json nothing comes off and nothing errors.

const PLAYER := "res://modules/player/scenes/player.tscn"
const BODY := "res://modules/player/scenes/player_body.tscn"

var _player: PlayerController
var _severing: LimbSevering


func before_test() -> void:
	Settings.reset()
	Corpse.enabled = true
	# Every qualifying shot severs, so a test can say which.
	var cfg := (Data.load_json(BloodEffects.CONFIG) as Dictionary).duplicate()
	cfg["shot_sever_chance"] = 1.0
	LimbSevering.use_config(cfg)
	var ground := auto_free(StaticBody3D.new()) as StaticBody3D
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	ground.add_child(shape)
	add_child(ground)
	ground.global_position = Vector3(0.0, -0.5, 0.0)
	_player = _body(Vector3.ZERO)
	_severing = auto_free(LimbSevering.new())
	add_child(_severing)


func after_test() -> void:
	Settings.reset()
	LimbSevering.use_config(Data.load_json(BloodEffects.CONFIG))
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


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## Where a bullet flying along `direction` at `height` above `body`'s feet stops on it, as the
## server's ray sees it: on the body's capsule.
func _hit_on(body: Node3D, height: float, direction: Vector3) -> Vector3:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var start := body.global_position + Vector3(0.0, height, 0.0) - direction * 5.0
	var query := PhysicsRayQueryParameters3D.create(start, start + direction * 10.0, PhysicsLayers.BULLETS)
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	assert_bool(hit.is_empty()).is_false()
	return hit["position"]


func _kill(body: PlayerController) -> Corpse:
	var corpse := Corpse.from_body(body, Vector3(0.0, 0.5, 1.0))
	(body.get_node("Body") as Node3D).visible = false
	(body.get_node("Shape") as CollisionShape3D).set_deferred(&"disabled", true)
	return corpse


## A shot as the weapon replays it: what the round carried and what the hit dealt (no more
## than the health that was left).
func _shot(body: Node3D, at: Vector3, direction: Vector3, round_damage: float, dealt := -1.0) -> void:
	var rifle: HitscanWeapon = auto_free(HitscanWeapon.new())
	rifle.stats = {"damage": round_damage}
	EventBus.publish(&"weapon.fired", {"weapon": rifle, "from": at - direction * 6.0, "to": at, "target": body, "collider": body, "damage": dealt if dealt >= 0.0 else round_damage, "round_damage": round_damage})


func _gone(corpse: Corpse, bone_name: String) -> bool:
	return corpse.skeleton.get_bone_pose_scale(corpse.skeleton.find_bone(bone_name)).x < 0.01


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


func test_a_killing_shot_in_the_shin_takes_it_off_a_frame_after_the_death() -> void:
	var at: Vector3 = await _hit_on(_player, 0.3, Vector3.FORWARD)
	var corpse := _kill(_player)
	await _frames(1)
	_shot(_player, at, Vector3.FORWARD, 30.0)
	await _frames(3)
	var pieces := _severing.pieces()
	assert_int(pieces.size()).is_equal(1)
	assert_bool(_gone(corpse, "LowerLeg_L") or _gone(corpse, "LowerLeg_R")).is_true()
	var piece := pieces[0]
	assert_int(piece.collision_layer).is_equal(PhysicsLayers.DEBRIS)
	assert_int(piece.collision_mask).is_equal(PhysicsLayers.SOLID | PhysicsLayers.GLASS)
	for mesh in piece.find_children("*", "GeometryInstance3D", true, false):
		assert_int((mesh as GeometryInstance3D).layers & RenderLayers.DEFAULT).is_equal(0)
	# It goes with its corpse.
	corpse.free()
	assert_bool(is_instance_valid(piece)).is_false()


func test_a_side_shot_at_shoulder_height_takes_the_arm() -> void:
	var at: Vector3 = await _hit_on(_player, 1.45, Vector3.RIGHT)
	var corpse := _kill(_player)
	_shot(_player, at, Vector3.RIGHT, 30.0)
	await _frames(3)
	assert_bool(_gone(corpse, "UpperArm_L")).is_true()


func test_chest_shots_from_the_front_never_take_the_arms_held_there() -> void:
	for height in [1.1, 1.2, 1.3, 1.4, 1.5]:
		var at: Vector3 = await _hit_on(_player, height, Vector3.FORWARD)
		assert_str(_severing.shot_limb(_corpse_for_probe(), at, Vector3.FORWARD, 100.0, LimbSevering.config())).is_empty()


var _probe: Corpse


## One ragdoll standing where the player is, to judge shots against without killing again.
func _corpse_for_probe() -> Corpse:
	if not is_instance_valid(_probe):
		_probe = Corpse.from_body(_player, Vector3.ZERO)
	return _probe


func test_a_weak_round_takes_nothing() -> void:
	var at: Vector3 = await _hit_on(_player, 0.3, Vector3.FORWARD)
	_kill(_player)
	_shot(_player, at, Vector3.FORWARD, 10.0)
	await _frames(3)
	assert_int(_severing.pieces().size()).is_equal(0)


func test_a_rifle_round_finishing_a_wounded_body_still_counts() -> void:
	var at: Vector3 = await _hit_on(_player, 0.3, Vector3.FORWARD)
	var corpse := _kill(_player)
	# The rifle's 25, of which only 10 was left to take.
	_shot(_player, at, Vector3.FORWARD, 25.0, 10.0)
	await _frames(3)
	assert_bool(_gone(corpse, "LowerLeg_L") or _gone(corpse, "LowerLeg_R")).is_true()


func test_a_shot_on_someone_else_takes_nothing_from_the_dead() -> void:
	var other := _body(Vector3(5.0, 0.0, 0.0))
	var at: Vector3 = await _hit_on(other, 0.3, Vector3.FORWARD)
	_shot(other, at, Vector3.FORWARD, 30.0)
	_kill(_player)
	await _frames(3)
	assert_int(_severing.pieces().size()).is_equal(0)


func test_a_blow_outside_the_window_takes_nothing() -> void:
	var cfg := LimbSevering.config().duplicate()
	cfg["sever_window_seconds"] = 0.05
	LimbSevering.use_config(cfg)
	var at: Vector3 = await _hit_on(_player, 0.3, Vector3.FORWARD)
	_shot(_player, at, Vector3.FORWARD, 30.0)
	# By the clock the window is measured on, not the scene's timers.
	var until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
	_kill(_player)
	await _frames(3)
	assert_int(_severing.pieces().size()).is_equal(0)
	# Old hits are let go of.
	assert_int(_severing.remembered_hits()).is_equal(0)


func test_a_blast_that_killed_nobody_takes_nothing() -> void:
	EventBus.publish(&"explosion", {"position": Vector3(0.0, 0.3, 0.8), "radius": 3.0})
	await _frames(3)
	assert_int(_severing.pieces().size()).is_equal(0)


func test_a_close_blast_takes_two_limbs_and_a_far_one_none() -> void:
	_kill(_player)
	EventBus.publish(&"explosion", {"position": Vector3(0.0, 0.3, 0.8), "radius": 3.0})
	await _frames(3)
	assert_int(_severing.pieces().size()).is_equal(int(LimbSevering.config()["blast_max_limbs"]))
	var far := _body(Vector3(10.0, 0.0, 0.0))
	_kill(far)
	EventBus.publish(&"explosion", {"position": Vector3(10.0, 0.3, float(LimbSevering.config()["blast_sever_radius"]) + 1.0), "radius": 6.0})
	await _frames(3)
	assert_int(_severing.pieces().size()).is_equal(int(LimbSevering.config()["blast_max_limbs"]))


func test_with_blood_off_nothing_comes_off() -> void:
	Settings.set_value("blood", false)
	_kill(_player)
	EventBus.publish(&"explosion", {"position": Vector3(0.0, 0.3, 0.5), "radius": 3.0})
	await _frames(3)
	assert_int(_severing.pieces().size()).is_equal(0)


func test_at_most_max_limbs_pieces_lie_about() -> void:
	var cap := int(LimbSevering.config()["max_limbs"])
	for i in cap + 2:
		var body := _body(Vector3(-25.0 + float(i) * 3.0, 0.0, 0.0))
		_kill(body)
		EventBus.publish(&"explosion", {"position": body.global_position + Vector3(0.0, 0.3, 0.8), "radius": 3.0})
		await _frames(2)
	assert_int(_severing.pieces().size()).is_equal(cap)


func test_a_severed_ragdoll_still_settles_cleanly() -> void:
	var corpse := _kill(_player)
	EventBus.publish(&"explosion", {"position": Vector3(0.0, 0.3, 0.8), "radius": 3.0})
	while not corpse.is_settled():
		await get_tree().physics_frame
	var gone := 0
	for limb: String in LimbRules.BLAST_LIMBS:
		if _gone(corpse, LimbRules.root_bone(limb)):
			gone += 1
	assert_int(gone).is_equal(int(LimbSevering.config()["blast_max_limbs"]))


func test_without_its_values_nothing_comes_off_and_nothing_errors() -> void:
	var partial := {"shot_sever_damage": 25.0}
	Log.begin_capture()
	LimbSevering.use_config(partial)
	var entries := Log.end_capture()
	assert_str(LogCapture.text(entries)).contains("missing required field")
	var severing: LimbSevering = auto_free(LimbSevering.new())
	add_child(severing)
	_kill(_player)
	EventBus.publish(&"explosion", {"position": Vector3(0.0, 0.3, 0.8), "radius": 3.0})
	severing.resolve(true)
	await _frames(3)
	assert_int(severing.pieces().size()).is_equal(0)


func test_a_shot_still_decides_when_a_blast_nearby_was_too_far_to_take_anything() -> void:
	var at: Vector3 = await _hit_on(_player, 0.3, Vector3.FORWARD)
	EventBus.publish(&"explosion", {"position": Vector3(0.0, 0.3, float(LimbSevering.config()["blast_sever_radius"]) + 2.0), "radius": 3.0})
	var corpse := _kill(_player)
	_shot(_player, at, Vector3.FORWARD, 30.0)
	await _frames(3)
	assert_bool(_gone(corpse, "LowerLeg_L") or _gone(corpse, "LowerLeg_R")).is_true()


func test_a_point_off_the_body_is_no_part_of_it() -> void:
	var corpse := _corpse_for_probe()
	assert_str(_severing.shot_limb(corpse, Vector3(-3.0, 1.2, 0.0), Vector3.RIGHT, 100.0, LimbSevering.config())).is_empty()

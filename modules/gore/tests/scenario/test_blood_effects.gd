extends GdUnitTestSuite
## Blood on clients: a shot into a body sprays out of its far side (more through the head) and
## marks the wall behind it; a shot into anything else does neither. A pool spreads under a
## ragdoll only once it has settled, on the ground below its chest. With the "Blood" setting
## off none of it happens.

const PLAYER := "res://modules/player/scenes/player.tscn"
## Where the wall behind the target stands (its front face), along -Z from the target.
const WALL_Z := -2.0

var _player: PlayerController
var _effects: BloodEffects


func before_test() -> void:
	Settings.reset()
	Corpse.enabled = true
	_box(Vector3(40.0, 1.0, 40.0), Vector3(0.0, -0.5, 0.0))
	_box(Vector3(6.0, 4.0, 0.5), Vector3(0.0, 2.0, WALL_Z - 0.25))
	_player = auto_free((load(PLAYER) as PackedScene).instantiate())
	_player.set_physics_process(false)
	# The player module puts players in the group as they spawn.
	_player.add_to_group(&"players")
	add_child(_player)
	_player.global_position = Vector3.ZERO
	_effects = auto_free(BloodEffects.new())
	add_child(_effects)
	_effects.set_process(false)


## The bodies only answer rays once a physics step has seen them.
func _step() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func after_test() -> void:
	Settings.reset()
	Corpse.enabled = DisplayServer.get_name() != "headless"
	for node in get_tree().get_nodes_in_group(Corpse.GROUP):
		node.free()


func _box(size: Vector3, at: Vector3) -> void:
	var body := auto_free(StaticBody3D.new()) as StaticBody3D
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = at


func _shot(to: Vector3, target: Node, collider: Node) -> Dictionary:
	return {"from": Vector3(to.x, to.y, 6.0), "to": to, "target": target, "collider": collider, "damage": 10.0}


func test_a_body_shot_sprays_out_of_the_far_side_and_marks_the_wall_behind() -> void:
	await _step()
	_effects.on_fired(_shot(Vector3(0.0, 1.0, 0.35), _player, _player))
	var drops := _effects.spray.live_count()
	assert_int(drops).is_equal(int(BloodEffects.config()["spray_count"]))
	for at in _effects.spray.live_positions():
		assert_float(at.z).is_less_equal(0.0)
	for v in _effects.spray.live_velocities():
		assert_float(v.z).is_less(0.0)
	assert_int(_effects.marks.count()).is_equal(1)
	var mark := _effects.marks.newest()
	assert_float(mark.global_position.z).is_equal_approx(WALL_Z, 0.01)
	assert_float(mark.global_position.y).is_equal_approx(1.0, 0.05)
	assert_vector(mark.global_transform.basis.y.normalized()).is_equal_approx(Vector3.BACK, Vector3.ONE * 0.01)
	# The body that was shot is never painted by marks around it.
	for mesh in _player.find_children("*", "GeometryInstance3D", true, false):
		assert_int((mesh as GeometryInstance3D).layers & mark.cull_mask).is_equal(0)


func test_a_headshot_sprays_more() -> void:
	await _step()
	var head := (_player.get_node("Head") as Node3D).global_position
	var to := Vector3(0.0, head.y + 0.05, 0.3)
	assert_bool(HitscanWeapon.is_headshot(_player, to)).is_true()
	_effects.on_fired(_shot(to, _player, _player))
	assert_int(_effects.spray.live_count()).is_equal(int(BloodEffects.config()["headshot_spray_count"]))


func test_nothing_bleeds_when_the_shot_hits_no_body() -> void:
	await _step()
	_effects.on_fired(_shot(Vector3(0.0, 1.0, WALL_Z), null, null))
	assert_int(_effects.spray.live_count()).is_equal(0)
	assert_int(_effects.marks.count()).is_equal(0)


func test_no_mark_when_nothing_is_within_reach_behind() -> void:
	await _step()
	# Shot along +X: nothing stands that way.
	_effects.on_fired({"from": Vector3(-6.0, 1.0, 0.0), "to": Vector3(-0.35, 1.0, 0.0), "target": _player, "collider": _player})
	assert_int(_effects.spray.live_count()).is_greater(0)
	assert_int(_effects.marks.count()).is_equal(0)


func test_a_grazing_shot_stretches_its_mark_along_the_surface() -> void:
	await _step()
	var cfg := BloodEffects.config()
	var square := BloodEffects.mark_shape(Vector3.FORWARD, Vector3.BACK, 0.5, cfg)
	var slant := BloodEffects.mark_shape(Vector3(1.0, 0.0, -0.3).normalized(), Vector3.BACK, 0.5, cfg)
	assert_float(square.y).is_equal_approx(square.x, 0.001)
	assert_float(slant.y).is_greater(slant.x * 1.5)
	assert_float(slant.y).is_less_equal(slant.x * float(cfg["mark_stretch_max"]) + 0.001)


func test_with_blood_off_a_body_shot_shows_nothing() -> void:
	await _step()
	Settings.set_value("blood", false)
	_effects.on_fired(_shot(Vector3(0.0, 1.0, 0.35), _player, _player))
	assert_int(_effects.spray.live_count()).is_equal(0)
	assert_int(_effects.marks.count()).is_equal(0)


func _ragdoll() -> Corpse:
	var corpse := Corpse.from_body(_player, Vector3.ZERO)
	(_player.get_node("Body") as Node3D).visible = false
	(_player.get_node("Shape") as CollisionShape3D).set_deferred(&"disabled", true)
	return corpse


func _settle(corpse: Corpse) -> void:
	while not corpse.is_settled():
		await get_tree().physics_frame


func test_a_pool_spreads_under_a_settled_ragdoll_only() -> void:
	await _step()
	var corpse := _ragdoll()
	await get_tree().physics_frame
	_effects.check_corpses()
	assert_int(_effects.marks.count()).is_equal(0)
	await _settle(corpse)
	_effects.check_corpses()
	assert_int(_effects.marks.count()).is_equal(1)
	# One pool per body, however often it is looked at.
	_effects.check_corpses()
	assert_int(_effects.marks.count()).is_equal(1)
	var chest := corpse.skeleton.global_transform * corpse.skeleton.get_bone_global_pose(corpse.skeleton.find_bone("Chest")).origin
	var pool := _effects.marks.newest()
	assert_float(pool.global_position.y).is_equal_approx(0.0, 0.05)
	assert_float(Vector2(pool.global_position.x - chest.x, pool.global_position.z - chest.z).length()).is_less(0.05)
	assert_vector(pool.global_transform.basis.y.normalized()).is_equal_approx(Vector3.UP, Vector3.ONE * 0.01)
	# The ragdoll is a copy of the body and keeps its layers: it lies in the pool, unpainted.
	var meshes := corpse.find_children("*", "GeometryInstance3D", true, false)
	assert_bool(meshes.is_empty()).is_false()
	for mesh in meshes:
		assert_int((mesh as GeometryInstance3D).layers & pool.cull_mask).is_equal(0)


func test_with_blood_off_no_pool_spreads() -> void:
	await _step()
	Settings.set_value("blood", false)
	var corpse := _ragdoll()
	await _settle(corpse)
	_effects.check_corpses()
	assert_int(_effects.marks.count()).is_equal(0)


func test_turning_blood_off_clears_what_is_already_shown() -> void:
	await _step()
	_effects.on_fired(_shot(Vector3(0.0, 1.0, 0.35), _player, _player))
	assert_int(_effects.marks.count()).is_equal(1)
	assert_int(_effects.spray.live_count()).is_greater(0)
	# Through the bus as the settings screen does it: set_value announces the change.
	Settings.set_value("blood", false)
	assert_int(_effects.marks.count()).is_equal(0)
	assert_int(_effects.spray.live_count()).is_equal(0)


func test_gear_given_to_a_body_later_is_kept_clean_too() -> void:
	var gun := MeshInstance3D.new()
	_player.add_child(gun)
	assert_int(gun.layers & 1).is_equal(0)
	assert_int(gun.layers & RenderLayers.NO_DECALS).is_equal(RenderLayers.NO_DECALS)
	# Not a body: the world keeps its layer.
	var rock: MeshInstance3D = auto_free(MeshInstance3D.new())
	add_child(rock)
	assert_int(rock.layers).is_equal(1)


func test_a_shot_through_your_own_head_throws_no_drops_at_your_eyes() -> void:
	var cfg := BloodEffects.config()
	assert_int(BloodEffects.spray_count(true, true, cfg)).is_equal(0)
	assert_int(BloodEffects.spray_count(true, false, cfg)).is_equal(int(cfg["headshot_spray_count"]))
	assert_int(BloodEffects.spray_count(false, true, cfg)).is_equal(int(cfg["spray_count"]))


func test_your_own_first_person_gun_stays_on_its_layer_and_marks_skip_it() -> void:
	PlayerBody.first_person(_player.get_node("Body"))
	var gun := MeshInstance3D.new()
	gun.mesh = BoxMesh.new()
	PlayerBody.weapon_socket(_player).add_child(gun)
	await get_tree().process_frame
	assert_int(gun.layers).is_equal(RenderLayers.FIRST_PERSON)
	BloodEffects.keep_clean(gun)
	assert_int(gun.layers).is_equal(RenderLayers.FIRST_PERSON)
	await _step()
	_effects.on_fired(_shot(Vector3(0.0, 1.0, 0.35), _player, _player))
	assert_int(gun.layers & _effects.marks.newest().cull_mask).is_equal(0)

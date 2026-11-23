extends GdUnitTestSuite
## #420: a soldier outside the players' camp never picks cover inside it (it could not walk
## there and would stand at the fence not firing).

const ENEMIES := "res://modules/enemies/enemies_module.gd"
const WEAPONS := "res://modules/weapons/weapons_module.gd"


func _box(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(auto_free(body))
	body.global_position = at


func test_no_cover_inside_the_camp_for_a_soldier_outside() -> void:
	_box(Vector3(0.0, -0.5, 0.0), Vector3(200.0, 1.0, 200.0))
	add_child(auto_free((load(WEAPONS) as GDScript).new()))
	var enemies: Node = auto_free((load(ENEMIES) as GDScript).new())
	add_child(enemies)
	var cfg: Dictionary = (Data.load_json(CampLayout.CONFIG) as Dictionary)["camp"]
	var camp := CampLayout.make(Vector3.ZERO, Vector3.FORWARD, Rect2(-20, -20, 40, 40), cfg)
	# The threat in the middle of the camp, a box just inside the gate between it and the
	# gate, and the soldier just outside the gate.
	var threat := Vector3.ZERO
	_box(camp.point(Vector2(1.5, camp.half - 2.5)) + Vector3.UP * 0.6, Vector3(2.4, 1.2, 0.3))
	await get_tree().physics_frame
	var at := camp.gate() + camp.out * 1.5 + camp.right * 1.0
	var squad: Array[Node] = enemies.call(&"server_spawn_squad", 1, at)
	await get_tree().process_frame
	var enemy := squad[0] as PlayerController
	enemy.global_position = at + Vector3.UP * 0.1
	await get_tree().physics_frame
	var brain := enemy.get_node("Brain") as EnemyBrain
	brain.keep_out = camp
	for leg in brain.find_cover_route(threat):
		assert_bool(camp.inside(leg)).override_failure_message("cover leg inside the camp at %s" % leg).is_false()

extends GdUnitTestSuite
## Your own body in first person keeps its arms and whatever they hold on the first-person
## render layer only (docs/decisions/0018), so a light at your chest can leave them out.
## Gear given later is caught too, and the dead body falls as an ordinary one.

const PLAYER := "res://modules/player/scenes/player.tscn"

var _player: PlayerController


func before_test() -> void:
	_player = auto_free((load(PLAYER) as PackedScene).instantiate())
	_player.set_physics_process(false)
	add_child(_player)


func after_test() -> void:
	Corpse.enabled = DisplayServer.get_name() != "headless"
	for node in get_tree().get_nodes_in_group(Corpse.GROUP):
		node.free()


func _layers(path: String) -> int:
	return (_player.get_node(path) as GeometryInstance3D).layers


func _gun() -> MeshInstance3D:
	var gun := MeshInstance3D.new()
	gun.mesh = BoxMesh.new()
	PlayerBody.weapon_socket(_player).add_child(gun)
	return gun


func test_the_arms_and_a_gun_given_later_are_on_the_first_person_layer_only() -> void:
	PlayerBody.first_person(_player.get_node("Body"))
	await get_tree().process_frame
	assert_int(_layers("Body/Skeleton/Arms")).is_equal(RenderLayers.FIRST_PERSON)
	# The torso is hidden but still casts its shadow; it stays a body like any other.
	assert_int(_layers("Body/Skeleton/Mesh") & RenderLayers.FIRST_PERSON).is_equal(0)
	var gun := _gun()
	await get_tree().process_frame
	assert_int(gun.layers).is_equal(RenderLayers.FIRST_PERSON)


func test_someone_elses_body_is_left_on_its_layers() -> void:
	var gun := _gun()
	await get_tree().process_frame
	assert_int(_layers("Body/Skeleton/Arms") & RenderLayers.FIRST_PERSON).is_equal(0)
	assert_int(gun.layers & RenderLayers.FIRST_PERSON).is_equal(0)


func test_your_own_dead_body_falls_off_the_first_person_layer() -> void:
	Corpse.enabled = true
	PlayerBody.first_person(_player.get_node("Body"))
	await get_tree().process_frame
	var corpse := Corpse.from_body(_player, Vector3.ZERO)
	assert_object(corpse).is_not_null()
	assert_object(corpse.find_child(PlayerBody.FIRST_PERSON_LAYER, true, false)).is_null()
	for mesh in corpse.find_children("*", "GeometryInstance3D", true, false):
		assert_int((mesh as GeometryInstance3D).layers & RenderLayers.FIRST_PERSON).is_equal(0)

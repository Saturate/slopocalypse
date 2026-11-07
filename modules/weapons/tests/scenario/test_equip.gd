extends GdUnitTestSuite
## One rifle per player: the logic sits at the camera (shots follow the aim) with no mesh,
## and the only visible rifle is in the body's hands with a muzzle the effects start from.

const PLAYER := "res://modules/player/scenes/player.tscn"
const MODULE := "res://modules/weapons/weapons_module.gd"

var _module: Node


func before_test() -> void:
	_module = auto_free((load(MODULE) as GDScript).new())
	add_child(_module)


func _spawn(local: bool) -> PlayerController:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	add_child(player)
	EventBus.publish(&"player.spawned", {"player": player, "local": local})
	return player


func _meshes_under(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _meshes_under(child)
	return count


func test_every_player_holds_exactly_one_visible_rifle() -> void:
	for local: bool in [true, false]:
		var player := _spawn(local)
		var camera_rifle := player.get_node("Head/Camera").get_child(-1)
		assert_object(camera_rifle).is_instanceof(HitscanWeapon)
		assert_int(_meshes_under(player.get_node("Head"))).is_equal(0)
		var held := ShotEffects.held_rifle(player)
		assert_object(held).is_not_null()
		assert_bool(held.visible).is_true()
		assert_object(held.get_node_or_null("Muzzle")).is_not_null()

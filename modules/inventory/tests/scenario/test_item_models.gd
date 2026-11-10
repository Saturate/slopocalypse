extends GdUnitTestSuite
## Items have 3D models for their icons and for lying on the ground: gear from the voxel kit,
## gun parts from the weapons module.

const INVENTORY := "res://modules/inventory/inventory_module.gd"
const WEAPONS := "res://modules/weapons/weapons_module.gd"

var _module: Node


func before_test() -> void:
	_module = auto_free((load(INVENTORY) as GDScript).new())
	add_child(_module)


func _has_mesh(node: Node3D) -> bool:
	return node is MeshInstance3D and (node as MeshInstance3D).mesh != null and (node as MeshInstance3D).mesh.get_surface_count() > 0


func test_gear_has_its_own_model() -> void:
	for item in ["medkit", "rig_light", "rig_heavy", "bag_small", "bag_large", "usb_drive"]:
		var model: Node3D = auto_free(_module.call(&"item_model", item))
		assert_bool(_has_mesh(model)).override_failure_message("%s has no model" % item).is_true()


func test_gun_parts_get_their_model_from_the_weapons_module() -> void:
	assert_object(_module.call(&"item_model", "opt_scope_4x")).is_null()
	add_child(auto_free((load(WEAPONS) as GDScript).new()))
	var model: Node3D = auto_free(_module.call(&"item_model", "opt_scope_4x"))
	assert_bool(_has_mesh(model)).is_true()


func test_every_gear_kind_builds() -> void:
	for kind in VoxGear.KINDS.size():
		var m := VoxGear.new().build({"kind": kind, "seed": 2})
		assert_bool(VoxGenerator.to_mesh(m).get_surface_count() > 0).is_true()

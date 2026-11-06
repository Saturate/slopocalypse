extends SceneTree
## Builds modules/weapons/scenes/rifle.tscn: the weapon node sits at the camera so shots
## start at the eye; the bevelled low-poly rifle and first-person arms sit in the lower
## right of the view.

const OUT := "res://modules/weapons/scenes/rifle.tscn"


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "Rifle"

	var model := Node3D.new()
	model.name = "Model"
	model.position = Vector3(0.16, -0.16, -0.38)
	model.scale = Vector3.ONE * 0.72
	root.add_child(model)

	var gun := MeshInstance3D.new()
	gun.name = "Gun"
	gun.mesh = RifleMesh.rifle()
	_view_model_layer(gun)
	model.add_child(gun)

	var arms := MeshInstance3D.new()
	arms.name = "Arms"
	arms.mesh = RifleMesh.arms()
	_view_model_layer(arms)
	model.add_child(arms)

	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.04, -0.64)
	model.add_child(muzzle)

	root.set_script(load("res://modules/weapons/scripts/hitscan_weapon.gd"))
	root.set("weapon_id", "rifle")
	root.set("model_path", NodePath("Model"))

	var result := SceneBuilder.pack_and_save(root, OUT)
	root.free()
	if result.error != OK:
		push_error(result.message)
		quit(1)
		return
	quit(0)


## View model meshes render on layer 2 (ViewModel.LAYER) so world-space lights such as the
## muzzle flash can skip them, and never cast shadows from the camera's position.
func _view_model_layer(mesh: MeshInstance3D) -> void:
	mesh.layers = ViewModel.LAYER
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

extends SceneTree
## Builds modules/weapons/scenes/rifle.tscn: the weapon node sits at the camera so shots
## start at the eye; the low-poly model is offset into the lower right of the view.

const OUT := "res://modules/weapons/scenes/rifle.tscn"


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "Rifle"

	var model := Node3D.new()
	model.name = "Model"
	# Smaller and further out than life size so it reads as held, not strapped to the face.
	model.position = Vector3(0.17, -0.16, -0.42)
	model.scale = Vector3.ONE * 0.7
	root.add_child(model)

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.15, 0.15, 0.16)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.3, 0.2)
	model.add_child(_part("Receiver", Vector3(0.06, 0.08, 0.32), Vector3(0, 0, 0), dark))
	model.add_child(_part("Barrel", Vector3(0.025, 0.025, 0.3), Vector3(0, 0.015, -0.3), dark))
	model.add_child(_part("Magazine", Vector3(0.04, 0.12, 0.06), Vector3(0, -0.09, -0.04), dark))
	model.add_child(_part("Stock", Vector3(0.05, 0.07, 0.18), Vector3(0, -0.02, 0.24), wood))
	model.add_child(_part("Grip", Vector3(0.04, 0.09, 0.04), Vector3(0, -0.07, 0.1), wood))

	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.015, -0.46)
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


func _part(part_name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = part_name
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mesh.mesh = box
	mesh.position = pos
	# The view model must never cast shadows onto the world from the camera's position.
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh

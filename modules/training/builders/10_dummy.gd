extends SceneTree
## Builds modules/training/scenes/dummy.tscn: a post-mounted torso and head that tips over
## when killed, with a health label above it.

const OUT := "res://modules/training/scenes/dummy.tscn"
const CONFIG := "res://modules/training/data/training.json"


func _initialize() -> void:
	var cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if not cfg is Dictionary:
		push_error("%s: could not parse" % CONFIG)
		quit(1)
		return

	var root := StaticBody3D.new()
	root.name = "Dummy"

	var straw := StandardMaterial3D.new()
	straw.albedo_color = Color(0.78, 0.68, 0.42)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.35, 0.26, 0.18)

	root.add_child(_mesh("Post", BoxMesh.new(), Vector3(0.1, 0.9, 0.1), Vector3(0, 0.45, 0), post_mat))

	# Pivot at the top of the post so the body tips backwards from there.
	var body := Node3D.new()
	body.name = "Body"
	body.position = Vector3(0, 0.9, 0)
	root.add_child(body)
	body.add_child(_mesh("Torso", BoxMesh.new(), Vector3(0.5, 0.7, 0.25), Vector3(0, 0.35, 0), straw))
	var head := SphereMesh.new()
	head.radius = 0.15
	head.height = 0.3
	body.add_child(_mesh("Head", head, Vector3.ONE, Vector3(0, 0.88, 0), straw))

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 1.75, 0.3)
	shape.shape = box
	shape.position = Vector3(0, 0.875, 0)
	root.add_child(shape)

	var health := Node.new()
	health.name = "Health"
	health.set_script(load("res://core/components/health_component.gd"))
	health.set("max_health", cfg["max_health"])
	root.add_child(health)

	var label := Label3D.new()
	label.name = "HealthLabel"
	label.position = Vector3(0, 2.1, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 96
	label.pixel_size = 0.004
	label.outline_size = 16
	label.no_depth_test = true
	root.add_child(label)

	root.set_script(load("res://modules/training/scripts/dummy_target.gd"))
	root.set("health_path", NodePath("Health"))
	root.set("label_path", NodePath("HealthLabel"))
	root.set("body_path", NodePath("Body"))
	root.set("respawn_seconds", cfg["respawn_seconds"])
	# Damage happens on the server; clients follow its health and knocked-over pose.
	root.add_child(NetSync.make([], ["Health:health", "Body:rotation"]))

	var result := SceneBuilder.pack_and_save(root, OUT)
	root.free()
	if result.error != OK:
		push_error(result.message)
		quit(1)
		return
	quit(0)


func _mesh(mesh_name: String, mesh: PrimitiveMesh, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	mesh.material = mat
	var inst := MeshInstance3D.new()
	inst.name = mesh_name
	inst.mesh = mesh
	inst.position = pos
	return inst

extends SceneTree
## Builds modules/example/scenes/example_marker.tscn. Run through `node tools/build-scenes.ts`.
## Builders run before autoloads can be named, so they report with push_error, not Log.

const OUT := "res://modules/example/scenes/example_marker.tscn"


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "ExampleMarker"

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = Vector3(1, 2, 1)
	mesh.mesh = box
	mesh.position = Vector3(0, 1, 0)
	root.add_child(mesh)

	var body := StaticBody3D.new()
	body.name = "Body"
	root.add_child(body)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	shape.position = mesh.position
	body.add_child(shape)

	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	var result := SceneBuilder.pack_and_save(root, OUT)
	root.free()
	if result.error != OK:
		push_error(result.message)
		quit(1)
		return
	quit(0)

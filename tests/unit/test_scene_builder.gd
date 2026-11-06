extends GdUnitTestSuite

const OUT := "user://test_scene_builder/"


func before() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	for f in DirAccess.get_files_at(OUT):
		DirAccess.remove_absolute(OUT + f)


func _tree() -> Node3D:
	var root := Node3D.new()
	root.name = "Root"
	var body := StaticBody3D.new()
	body.name = "Body"
	root.add_child(body)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	return root


func test_counts_every_node_in_the_tree() -> void:
	var root := _tree()
	assert_int(SceneBuilder.count_nodes(root)).is_equal(3)
	root.free()


func test_saves_a_complete_scene() -> void:
	var root := _tree()
	var result := SceneBuilder.pack_and_save(root, OUT + "ok.tscn")
	root.free()
	assert_int(result.error).is_equal(OK)
	var loaded: PackedScene = load(OUT + "ok.tscn")
	var inst := loaded.instantiate()
	assert_int(SceneBuilder.count_nodes(inst)).is_equal(3)
	inst.free()


func test_refuses_to_save_when_nodes_would_be_dropped() -> void:
	var root := _tree()
	var result := SceneBuilder.pack_and_save(root, OUT + "dropped.tscn", false)
	root.free()
	assert_int(result.error).is_not_equal(OK)
	assert_str(result.message).contains("dropped")
	assert_bool(FileAccess.file_exists(OUT + "dropped.tscn")).is_false()


func test_does_not_inline_instanced_scenes() -> void:
	var inner := _tree()
	SceneBuilder.pack_and_save(inner, OUT + "inner.tscn")
	inner.free()
	var outer := Node3D.new()
	outer.name = "Outer"
	var packed: PackedScene = load(OUT + "inner.tscn")
	outer.add_child(packed.instantiate())
	var result := SceneBuilder.pack_and_save(outer, OUT + "outer.tscn")
	outer.free()
	assert_int(result.error).is_equal(OK)
	var text := FileAccess.get_file_as_string(OUT + "outer.tscn")
	assert_str(text).contains("inner.tscn")
	assert_str(text).not_contains("BoxShape3D")


func test_resaving_keeps_the_file_byte_identical() -> void:
	var a := _tree()
	SceneBuilder.pack_and_save(a, OUT + "stable.tscn")
	a.free()
	var first := FileAccess.get_file_as_string(OUT + "stable.tscn")
	var b := _tree()
	SceneBuilder.pack_and_save(b, OUT + "stable.tscn")
	b.free()
	assert_str(FileAccess.get_file_as_string(OUT + "stable.tscn")).is_equal(first)

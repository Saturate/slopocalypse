extends GdUnitTestSuite
## Voxel materials: the data file's entries, the indices voxels store, and the shed giving
## each part of itself the right material.

const W := 4.5
const D := 3.5
const WH := 2.6


func _shed(material: int, glass: int = 0) -> VoxelModel:
	return VoxShed.new().build({"seed": 3, "width": W, "depth": D, "wall_height": WH, "pitch": 0.55, "door": 1, "windows": 2.0, "voxel": 0.1, "material": material, "glass": glass})


func _name_at(m: VoxelModel, p: Vector3) -> String:
	return str(VoxMaterials.at(m.material_at(p))["name"])


func test_names_map_to_their_place_in_the_list() -> void:
	var all := VoxMaterials.all()
	assert_str(str(all[0]["name"])).is_equal("default")
	for i in all.size():
		assert_int(VoxMaterials.index_of(str(all[i]["name"]))).is_equal(i)
	assert_float(float(VoxMaterials.named("concrete")["min_bullet_damage"])).is_equal(60.0)


func test_fills_store_the_material_set_before_them() -> void:
	var m := VoxelModel.new()
	m.setup(Vector3(1, 1, 1), 0.1)
	m.set_material(VoxMaterials.index_of("brick"))
	m.fill_box(Vector3(-0.5, 0, -0.5), Vector3(0.5, 0.5, 0.5), Color.RED, 0.0, 1)
	assert_str(_name_at(m, Vector3(0, 0.25, 0))).is_equal("brick")
	assert_str(_name_at(m, Vector3(0, 0.75, 0))).is_equal("default")
	m.mark_box(Vector3(-0.5, 0, -0.5), Vector3(0.5, 1, 0.5), VoxMaterials.index_of("wood"))
	assert_str(_name_at(m, Vector3(0, 0.25, 0))).is_equal("wood")


func test_a_shed_gives_each_part_its_material() -> void:
	var m := _shed(0)
	assert_str(_name_at(m, Vector3(0, 0.07, 0))).is_equal("concrete")
	# The back wall (no window there with two windows).
	assert_str(_name_at(m, Vector3(0, 1.0, D / 2 - 0.05))).is_equal("wood")
	# The left window's pane, half a wall in.
	assert_str(_name_at(m, Vector3(-W / 2 + 0.1, 1.5, 0))).is_equal("window_glass")
	# The lintel over the door.
	assert_str(_name_at(m, Vector3(0, 2.2, -D / 2))).is_equal("wood")
	assert_str(_name_at(m, _top_at(m, 0.0, 0.05))).is_equal("sheet_metal")


func test_wall_choice_and_panes_follow_the_parameters() -> void:
	assert_str(_name_at(_shed(1), Vector3(0, 1.0, D / 2 - 0.05))).is_equal("concrete")
	assert_str(_name_at(_shed(2), Vector3(0, 1.0, D / 2 - 0.05))).is_equal("brick")
	assert_str(_name_at(_shed(0, 1), Vector3(-W / 2 + 0.1, 1.5, 0))).is_equal("security_glass")


func test_an_entry_missing_a_field_is_rejected() -> void:
	var entry := (VoxMaterials.named("wood") as Dictionary).duplicate()
	entry.erase("pass")
	Log.begin_capture()
	var ok := VoxMaterials.validate([entry])
	var logged := LogCapture.text(Log.end_capture())
	assert_bool(ok).is_false()
	assert_str(logged).contains("pass")


## The highest filled point straight down at (x, z): the roof there.
func _top_at(m: VoxelModel, x: float, z: float) -> Vector3:
	var y := 6.0
	while y > 0.0:
		if m.material_at(Vector3(x, y, z)) != 0:
			return Vector3(x, y, z)
		y -= 0.05
	return Vector3(x, 0, z)

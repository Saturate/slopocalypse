extends GdUnitTestSuite
## The range's fixed row: buildings in the listed order along one side of the road, apart
## by the gap, doors to the road, each with its listed material and panes.


static func _road(metres: float) -> Vector3:
	return Vector3(0.0, 0.0, -metres)


func test_a_row_keeps_its_order_spacing_and_materials() -> void:
	var cfg := {"gap": 4.0, "row_off_road": 10.0, "row": [
		{"material": "wood", "width": 5.0, "depth": 4.0},
		{"material": "brick", "glass": "security_glass", "width": 6.0, "depth": 4.0},
	]}
	var row := MissionLayout.buildings(cfg, 1, _road, 100.0)
	assert_int(row.size()).is_equal(2)
	assert_str(str(row[0]["material"])).is_equal("wood")
	assert_str(str(row[0]["glass"])).is_equal("window_glass")
	assert_str(str(row[1]["glass"])).is_equal("security_glass")
	var a: Vector3 = row[0]["position"]
	var b: Vector3 = row[1]["position"]
	# Centres apart by half of each width plus the gap, all on the +x side, 10 m + half a depth out.
	assert_float(absf(b.z - a.z)).is_equal_approx(5.0 / 2.0 + 4.0 + 6.0 / 2.0, 0.001)
	assert_float(a.x).is_equal_approx(12.0, 0.001)


func test_the_material_line_reads_the_rules() -> void:
	var text := (load("res://modules/range/types/test_range.gd") as GDScript).call(&"describe", VoxMaterials.named("concrete")) as String
	assert_str(text).contains("only chips under 60")
	assert_str((load("res://modules/range/types/test_range.gd") as GDScript).call(&"describe", VoxMaterials.named("wood")) as String).contains("go through")

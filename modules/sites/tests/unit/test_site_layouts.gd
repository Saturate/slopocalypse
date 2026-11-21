extends GdUnitTestSuite
## Every site kind in the shipped map recipes has a layout, and every piece of it stays inside
## that kind's footprint whichever side the site's track leaves by, mirrored or not.

const RECIPES: Array[String] = ["res://modules/world/data/maps/grassland.json", "res://modules/world/data/maps/mixed.json"]
const YAWS: Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]


func _config() -> Dictionary:
	return Data.load_json(SiteLayout.CONFIG)


func _kinds(recipe: String) -> Dictionary:
	var data: Dictionary = Data.load_json(recipe)
	return (data["sites"] as Dictionary)["kinds"]


func test_every_site_kind_in_each_recipe_has_a_layout() -> void:
	var layouts: Dictionary = _config()["kinds"]
	for recipe in RECIPES:
		for kind: String in _kinds(recipe):
			assert_bool(layouts.has(kind)).override_failure_message("%s: no layout for %s" % [recipe, kind]).is_true()


func test_every_piece_names_a_kit_generator() -> void:
	var layouts: Dictionary = _config()["kinds"]
	for kind: String in layouts:
		for piece: Dictionary in (layouts[kind] as Dictionary)["pieces"]:
			assert_object(VoxCatalog.by_name(str(piece["generator"]))).override_failure_message("%s: %s" % [kind, piece["generator"]]).is_not_null()


func test_every_piece_fits_its_kinds_footprint() -> void:
	var layouts: Dictionary = _config()["kinds"]
	for recipe in RECIPES:
		var kinds := _kinds(recipe)
		for kind: String in kinds:
			var size: Array = (kinds[kind] as Dictionary)["size"]
			var half := Vector2(float(size[0]), float(size[1])) / 2.0
			for piece: Dictionary in (layouts[kind] as Dictionary)["pieces"]:
				var extent := _largest_extent(piece)
				for toward in YAWS:
					for mirror: bool in [false, true]:
						var t := Transform3D(Basis(Vector3.UP, SiteLayout.site_yaw(toward)), Vector3.ZERO) * SiteLayout.piece_transform(piece, mirror)
						for corner: Vector3 in _corners(extent):
							var p := t * corner
							var inside := absf(p.x) <= half.x and absf(p.z) <= half.y
							assert_bool(inside).override_failure_message("%s %s: %s pokes out at %s (footprint %s)" % [recipe.get_file(), kind, piece["generator"], p, half * 2.0]).is_true()


func test_a_site_faces_its_track() -> void:
	for toward in YAWS:
		var front := Basis(Vector3.UP, SiteLayout.site_yaw(toward)) * Vector3.FORWARD
		assert_vector(front).is_equal_approx(toward, Vector3.ONE * 0.0001)


## The piece's model grid at the largest its ranges allow, in model space (x and z centred).
func _largest_extent(piece: Dictionary) -> AABB:
	var params: Dictionary = (piece.get("params", {}) as Dictionary).duplicate()
	var ranges: Dictionary = piece.get("ranges", {})
	for key: String in ranges:
		params[key] = float((ranges[key] as Array)[1])
	var model := VoxCatalog.by_name(str(piece["generator"])).build(params)
	var size := Vector3(model.cells()) * model.voxel_size()
	return AABB(Vector3(-size.x / 2.0, 0.0, -size.z / 2.0), size)


func _corners(box: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for x: float in [box.position.x, box.end.x]:
		for z: float in [box.position.z, box.end.z]:
			out.append(Vector3(x, 0.0, z))
	return out


func test_the_shipped_layouts_have_every_field_they_need() -> void:
	assert_array(SiteLayout.check(_config())).is_empty()


func test_a_piece_missing_a_field_or_naming_no_generator_is_reported() -> void:
	var cfg := {"kinds": {"farm": {"pieces": [{"generator": "VoxNothing", "at": [0.0, 0.0, 0.0], "yaw": 0.0, "params": {}}, {"generator": "VoxShed", "yaw": 0.0, "params": {}}]}}}
	var problems := SiteLayout.check(cfg)
	assert_int(problems.size()).is_equal(2)

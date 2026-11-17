extends GdUnitTestSuite
## A city on the ground: every planned building goes up (a few a frame), standing on the
## pavement; pavements are a kerb high and solid; trees are kept off the whole footprint.

const MODULE := "res://modules/city/city_module.gd"

var _cfg: Dictionary


func before_test() -> void:
	_cfg = Data.load_json("res://modules/city/data/city.json")
	# Small and quick: one building a frame, a 2 x 2 grid (no square).
	_cfg["blocks"] = 2.0
	_cfg["size"] = 100.0
	_cfg["builds_per_frame"] = 1.0


func _site() -> CitySite:
	var site: CitySite = auto_free(CitySite.new())
	site.config = _cfg
	add_child(site)
	return site


func test_buildings_go_up_a_few_a_frame_until_all_stand() -> void:
	var site := _site()
	var planned := (site.plan["buildings"] as Array).size()
	assert_int(planned).is_greater(0)
	assert_int(site.buildings.size()).is_equal(0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(site.buildings.size()).is_between(1, 2)
	site.build_all()
	assert_int(site.buildings.size()).is_equal(planned)
	assert_int(site.pending()).is_equal(0)
	for b in site.buildings:
		assert_float(b.position.y).is_equal_approx(CitySite.KERB, 0.001)


func test_pavements_are_a_kerb_high_and_solid() -> void:
	var site := _site()
	await get_tree().physics_frame
	var block: Rect2 = site.plan["blocks"][0]
	var p := Vector3(block.position.x + 1.0, 0.0, block.get_center().y)
	var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN, PhysicsLayers.SOLID)
	var hit := site.get_world_3d().direct_space_state.intersect_ray(query)
	assert_bool(hit.is_empty()).is_false()
	assert_float((hit["position"] as Vector3).y).is_equal_approx(CitySite.KERB, 0.01)


func test_clearings_cover_the_whole_footprint() -> void:
	var module: GDScript = load(MODULE)
	var where := Transform3D(Basis(Vector3.UP, 0.4), Vector3(30, 2, -80))
	var circles: Array = module.call(&"clearings", where, 100.0)
	for local: Vector3 in [Vector3(-50, 0, -50), Vector3(50, 0, 50), Vector3(0, 0, 0), Vector3(49, 0, -13)]:
		var p := where * local
		var covered := false
		for c: Dictionary in circles:
			var at: Vector3 = c["at"]
			covered = covered or Vector2(p.x - at.x, p.z - at.z).length() <= float(c["radius"])
		assert_bool(covered).is_true()

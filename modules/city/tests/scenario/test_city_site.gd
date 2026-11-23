extends GdUnitTestSuite
## A city on the ground: every planned building goes up (a few a frame), standing on the
## pavement; pavements are a kerb high and solid; trees are kept off the whole footprint; the
## gateways through the street fronts are open (a round and a person go through into the
## courtyard); street trees stand solid; the lamps' spots are published for the lights.

const MODULE := "res://modules/city/city_module.gd"
const PLAYER := "res://modules/player/scenes/player.tscn"

var _cfg: Dictionary
var _published: Array[Dictionary] = []


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


func _ray(site: CitySite, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(site.to_global(from), site.to_global(to), PhysicsLayers.SOLID)
	return site.get_world_3d().direct_space_state.intersect_ray(query)


## A gateway in a front facing -z, with the courtyard behind it: the street side is low z.
func _gateway(site: CitySite) -> Rect2:
	for b: Dictionary in site.plan["buildings"]:
		if b.has("gateway") and b["facing"] == Vector2(0, -1):
			return b["gateway"]
	return Rect2()


func test_a_round_goes_through_a_gateway_into_the_courtyard_and_not_beside_it() -> void:
	var site := _site()
	site.build_all()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var gate := _gateway(site)
	assert_bool(gate.size == Vector2.ZERO).is_false()
	var y := CitySite.KERB + 1.6
	var x := gate.get_center().x
	assert_bool(_ray(site, Vector3(x, y, gate.position.y - 2.0), Vector3(x, y, gate.end.y + 3.0)).is_empty()).is_true()
	# Higher up, and a few metres along the front, it's building.
	assert_bool(_ray(site, Vector3(x, y + 3.0, gate.position.y - 2.0), Vector3(x, y + 3.0, gate.end.y + 3.0)).is_empty()).is_false()
	assert_bool(_ray(site, Vector3(x + 4.0, y, gate.position.y - 2.0), Vector3(x + 4.0, y, gate.end.y + 3.0)).is_empty()).is_false()


func test_a_person_walks_through_a_gateway_into_the_courtyard() -> void:
	var site := _site()
	site.build_all()
	await get_tree().physics_frame
	var gate := _gateway(site)
	var player: PlayerController = (load(PLAYER) as PackedScene).instantiate()
	add_child(player)
	# On the pavement in front, facing +z, through the gateway.
	player.rotation.y = PI
	player.global_position = site.to_global(Vector3(gate.get_center().x, CitySite.KERB + 0.05, gate.position.y - 1.5))
	for i in 10:
		await get_tree().physics_frame
	player.intent().move = Vector2(0, 1)
	for i in 240:
		await get_tree().physics_frame
	var at := site.to_local(player.global_position)
	var in_yard := false
	for yard: Rect2 in site.plan["yards"]:
		in_yard = in_yard or yard.has_point(Vector2(at.x, at.z))
	assert_bool(in_yard).override_failure_message("ended at %s, gateway %s" % [at, gate]).is_true()
	player.free()


func test_street_trees_stand_solid_in_the_pavement() -> void:
	var site := _site()
	await get_tree().physics_frame
	var trees: Array = site.plan["trees"]
	assert_int(trees.size()).is_greater(0)
	var at: Vector2 = trees[0]
	var hit := _ray(site, Vector3(at.x - 2.0, 1.2, at.y), Vector3(at.x + 2.0, 1.2, at.y))
	assert_bool(hit.is_empty()).is_false()


func _on_lamp_spots(p: Dictionary) -> void:
	_published.append(p)


func test_the_city_says_where_its_lamps_go() -> void:
	_published.clear()
	EventBus.subscribe(&"city.lamp_spots", _on_lamp_spots)
	var module: Node = auto_free((load(MODULE) as GDScript).new())
	module.set(&"config", _cfg)
	add_child(module)
	var where := Transform3D(Basis(Vector3.UP, 0.5), Vector3(20, 3, -40))
	module.call(&"place", where)
	module.call(&"publish_lamps")
	EventBus.unsubscribe(&"city.lamp_spots", _on_lamp_spots)
	assert_int(_published.size()).is_equal(1)
	var site: CitySite = module.get(&"site")
	var spots: Array = _published[0]["spots"]
	assert_int(spots.size()).is_equal((site.plan["lamps"] as Array).size())
	assert_int(spots.size()).is_greater(4)
	for i in spots.size():
		var spot: Transform3D = spots[i]
		var lamp: Dictionary = site.plan["lamps"][i]
		var local := site.global_transform.affine_inverse() * spot
		# On the pavement's top, its arm (+x) out over the street.
		assert_float(local.origin.y).is_equal_approx(CitySite.KERB, 0.001)
		var arm := local.basis * Vector3.RIGHT
		var out: Vector2 = lamp["out"]
		assert_float(Vector2(arm.x, arm.z).dot(out)).is_greater(0.99)

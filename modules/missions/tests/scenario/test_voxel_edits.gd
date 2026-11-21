extends GdUnitTestSuite
## Destruction reaches every copy of a building as the server's integer voxel edits: clients
## change their voxels only through them, and someone joining late rebuilds the same cells
## from the edit log in the layout entry.

const MISSIONS := "res://modules/missions/missions_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"

var _missions: Node


func before_test() -> void:
	add_child(auto_free((load(INVENTORY) as GDScript).new()))
	_missions = auto_free((load(MISSIONS) as GDScript).new())
	add_child(_missions)
	EventBus.publish(&"world.ready", {"spawn": Vector3.ZERO})


## A roadside place 300 m out: an empty footprint, the road to its -x.
static func _place() -> Dictionary:
	return {"centre": Vector3(0.0, 0.0, -300.0), "footprint": Rect2(0.0, -300.0, 0.0, 0.0), "toward": Vector3.LEFT}


func _entry(material: String) -> Dictionary:
	var cfg: Dictionary = (_missions.get(&"config") as Dictionary)["buildings"]
	var entry: Dictionary = MissionLayout.buildings(cfg, 3, _place())[0]
	entry["material"] = material
	entry["windows"] = 2
	entry["position"] = Vector3(0, 0, -40)
	return entry


## The missions module builds and owns it, so hits reach it the way they do in a run.
func _owned(material: String) -> MissionBuilding:
	_missions.set(&"buildings", [_entry(material)])
	_missions.call(&"_build_buildings")
	return (_missions.call(&"building_nodes") as Array[MissionBuilding])[0]


## A copy built from `entry` the way a late joiner builds it.
func _late(entry: Dictionary, parent: Node) -> MissionBuilding:
	var b := MissionBuilding.new()
	b.spec = entry.duplicate(true)
	parent.add_child(b)
	b.global_position = entry["position"]
	return b


## Rounds along the right-hand wall and two charges at it, all sent as the game sends them.
func _shoot_up(b: MissionBuilding) -> void:
	var w := float(b.spec["width"])
	var inward := -b.global_transform.basis.x
	for i in 50:
		var to := b.global_transform * Vector3(w / 2.0, 0.4 + fmod(i * 0.137, 1.0) * 1.8, -1.2 + fmod(i * 0.291, 1.0) * 2.4)
		EventBus.publish(&"weapon.fired", {"holder": null, "from": to - inward * 8.0, "to": to, "collider": b, "damage": 25.0})
	for z: float in [-0.8, 0.9]:
		Net.server_broadcast(&"explosion", {"position": b.global_transform * Vector3(w / 2.0 + 0.4, 1.0, z), "radius": 2.5})
	await get_tree().process_frame


func test_a_late_joiner_has_the_same_voxels_after_shots_and_charges() -> void:
	for material: String in ["wood", "brick", "concrete"]:
		var b := _owned(material)
		var untouched := b.grid_hash()
		await _shoot_up(b)
		assert_int(b.grid_hash()).override_failure_message(material + ": nothing changed").is_not_equal(untouched)
		var entry: Dictionary = (_missions.get(&"buildings") as Array)[0]
		assert_int(VoxelModel.edit_count(entry["edits"])).is_greater(0)
		var late: MissionBuilding = auto_free(_late(entry, self))
		assert_int(late.grid_hash()).override_failure_message(material).is_equal(b.grid_hash())


func test_past_max_edits_the_log_starts_from_a_snapshot_and_still_matches() -> void:
	var b := _owned("brick")
	b.max_edits = 5
	await _shoot_up(b)
	var entry: Dictionary = (_missions.get(&"buildings") as Array)[0]
	assert_int((entry["edits_base"] as PackedByteArray).size()).is_greater(0)
	assert_int(VoxelModel.edit_count(entry["edits"])).is_less_equal(5)
	var late: MissionBuilding = auto_free(_late(entry, self))
	assert_int(late.grid_hash()).is_equal(b.grid_hash())


func test_an_edit_is_under_sixteen_bytes_whatever_it_removes() -> void:
	var b := _owned("wood")
	var all := b.model().cells()
	assert_int(VoxelModel.edit_cut_box(Vector3i.ZERO, all).size()).is_less(16)
	assert_int(VoxelModel.edit_cut_sphere(Vector3i(3, 4, 5), 0).size()).is_less(16)


func test_a_client_changes_its_voxels_only_through_the_servers_edits() -> void:
	# A subtree with its own multiplayer as a client (connecting to nobody), so the copy in
	# it is not the server.
	var client_root: Node = auto_free(Node.new())
	add_child(client_root)
	var api := SceneMultiplayer.new()
	var peer := ENetMultiplayerPeer.new()
	assert_int(peer.create_client("127.0.0.1", 1)).is_equal(OK)
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, client_root.get_path())
	var server := _late(_entry("brick"), self)
	var client := _late(_entry("brick"), client_root)
	assert_bool(client.multiplayer.is_server()).is_false()
	assert_int(client.grid_hash()).is_equal(server.grid_hash())
	var w := float(server.spec["width"])
	var inward := -server.global_transform.basis.x
	for i in 30:
		var to := server.global_transform * Vector3(w / 2.0, 0.4 + fmod(i * 0.137, 1.0) * 1.8, -1.0 + fmod(i * 0.291, 1.0) * 2.0)
		var before := client.grid_hash()
		server.bullet_mark(to, inward)
		client.bullet_mark(to, inward)
		var knocked := server.server_brick_hit(to, inward, 60.0)
		server.knock_out(knocked, false)
		client.knock_out(knocked, false)
		# Its own effects never change its voxels; the server's edits do.
		assert_int(client.grid_hash()).is_equal(before)
		client.apply_server_edits(server.take_unsent_edits())
		assert_int(client.grid_hash()).is_equal(server.grid_hash())
	var broke := server.server_blast(server.global_transform * Vector3(w / 2.0 + 0.3, 1.0, 0.0), 3.0, 2000.0, 1.6)
	assert_array(broke).is_not_empty()
	server.break_segments(broke)
	client.break_segments(broke)
	client.apply_server_edits(server.take_unsent_edits())
	assert_int(client.grid_hash()).is_equal(server.grid_hash())
	get_tree().set_multiplayer(null, client_root.get_path())
	peer.close()
	server.free()

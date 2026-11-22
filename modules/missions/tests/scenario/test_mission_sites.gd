extends GdUnitTestSuite
## Missions at the map's sites, on the real map: the zone centres on the farm, the mission's
## buildings and guards stand off the farm's pad and yard and off the roads and leave the
## pad's ground as it was, the group is set down on the site's own track a short walk out of
## the zone, and the next board still goes to sites.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
const MISSIONS := "res://modules/missions/missions_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
const ENEMIES := "res://modules/enemies/enemies_module.gd"

var _world: Node3D
var _voxels: VoxelWorld
var _missions: Node
var _spawn := Vector3.ZERO
## The longest walk from the drop-off to the zone's edge any site may ask for, metres.
const MAX_WALK := 120.0


func before_test() -> void:
	_world = await VoxelWorld.add_and_wait(self, WORLD)
	_voxels = _world.get_node("Terrain")
	EventBus.subscribe(&"player.move_requested", _on_move)
	add_child(auto_free((load(INVENTORY) as GDScript).new()))
	add_child(auto_free((load(ENEMIES) as GDScript).new()))
	_missions = (load(MISSIONS) as GDScript).new()
	add_child(_missions)
	_spawn = (_world.get_node("SpawnPoint") as Node3D).global_position
	EventBus.publish(&"world.ready", {"spawn": _spawn})


func after_test() -> void:
	EventBus.unsubscribe(&"player.move_requested", _on_move)
	_missions.free()
	_world.free()


func _on_move(p: Dictionary) -> void:
	(p["player"] as Node3D).global_position = p["position"]


## Rides out to the guarded lodge at a farm, whatever its distance.
func _ride_out_to_a_farm() -> Dictionary:
	var player: PlayerController = auto_free((load(PLAYER) as PackedScene).instantiate())
	player.set_meta(&"peer_id", 71)
	player.add_to_group(&"players")
	add_child(player)
	player.set_physics_process(false)
	player.global_position = _spawn
	var cfg: Dictionary = (_missions.get(&"config") as Dictionary).duplicate(true)
	var lodge: Dictionary = (cfg["missions"] as Array).filter(func(t: Dictionary) -> bool: return t["place"] == "Farm lodge")[0]
	lodge["distance"] = [0.0, 100000.0]
	cfg["missions"] = [lodge]
	cfg["offered"] = 1.0
	var offers: Array = (load(MISSIONS) as GDScript).call(&"roll_offers", cfg, 1, _missions.get(&"sites"), _spawn)
	assert_int(offers.size()).is_equal(1)
	_missions.set(&"offers", offers)
	assert_bool(_missions.call(&"server_choose", 71, 0)).is_true()
	assert_bool(_missions.call(&"server_ride_out")).is_true()
	await get_tree().process_frame
	return offers[0]["site"]


## How far `at` lies from the nearest point of `foot`.
static func _off(foot: Rect2, at: Vector3) -> float:
	var nearest := Vector2(clampf(at.x, foot.position.x, foot.end.x), clampf(at.z, foot.position.y, foot.end.y))
	return nearest.distance_to(Vector2(at.x, at.z))


func test_the_zone_centres_on_the_farm_with_buildings_and_guards_off_its_pad() -> void:
	var site: Dictionary = await _ride_out_to_a_farm()
	assert_str(str(site["kind"])).is_equal("farm")
	var centre: Vector3 = site["centre"]
	var zone: Vector3 = _missions.get(&"zone")
	assert_float(Vector2(zone.x - centre.x, zone.z - centre.z).length()).is_less(0.01)
	var foot: Rect2 = site["footprint"]
	var buildings: Array = _missions.get(&"buildings")
	assert_int(buildings.size()).is_greater(1)
	for entry: Dictionary in buildings:
		var at: Vector3 = entry["position"]
		# The whole building off the pad (the yard lies inside it) and off every road.
		assert_float(_off(foot, at)).is_greater_equal(float(entry["radius"]))
		assert_bool(_voxels.near_road(at, float(entry["radius"]), 0.0)).is_false()
		# Nor on anyone else's levelled ground (the mission's own pads are under no owner).
		assert_bool(_voxels.is_claimed(at, float(entry["radius"]), &"")).is_false()
	var guards := get_tree().get_nodes_in_group(&"enemies").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	assert_int(guards.size()).is_greater(0)
	for g: Node in guards:
		var at := (g as Node3D).global_position
		assert_bool(foot.has_point(Vector2(at.x, at.z))).override_failure_message("a guard stands on the farm's pad at %s" % at).is_false()


func test_the_farm_mission_is_one_fenced_place_with_its_track_through_the_gate() -> void:
	var site: Dictionary = await _ride_out_to_a_farm()
	var foot: Rect2 = site["footprint"]
	var cfg: Dictionary = _missions.get(&"config")
	var off: Array = cfg["buildings"]["off_site"]
	for entry: Dictionary in _missions.get(&"buildings"):
		var at: Vector3 = entry["position"]
		assert_bool(foot.grow(float(off[1]) + float(entry["radius"]) + 0.01).has_point(Vector2(at.x, at.z))).override_failure_message("a building at %s, far out from the farm's pad" % at).is_true()
	var fence: Array = _missions.get(&"_fence_nodes")
	assert_int(fence.size()).is_greater(8)
	var ring := Rect2(Vector2((fence[0] as Node3D).global_position.x, (fence[0] as Node3D).global_position.z), Vector2.ZERO)
	for node: VoxPiece in fence:
		var at := node.global_position
		if node.get_meta(&"gate", false):
			continue
		ring = ring.expand(Vector2(at.x, at.z))
		var half := float(node.params["length"]) / 2.0
		# No run on a road or track: where the farm's track leaves, the fence has its gate.
		for t: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			var p := node.global_transform * Vector3(half * t, 0.0, 0.0)
			assert_bool(_voxels.near_road(p, 0.0, 0.0)).override_failure_message("a fence run on a road at %s" % p).is_false()
		# Standing on the ground at its middle, neither in the air nor sunk out of sight.
		assert_float(at.y).is_between(_voxels.surface_height(at.x, at.z) - 0.5, _voxels.surface_height(at.x, at.z))
	assert_bool(ring.encloses(foot)).is_true()
	var track: Dictionary = (_missions.get(&"sites") as Array)[int(site["index"])]["track"]
	if not track.is_empty():
		var points: PackedVector2Array = track["points"]
		var leaves := Array(points).any(func(p: Vector2) -> bool: return not ring.has_point(p))
		assert_bool(leaves).override_failure_message("the farm's track never leaves the fence").is_true()


func test_the_drop_off_is_on_the_farms_track_a_walk_outside_the_zone() -> void:
	var site: Dictionary = await _ride_out_to_a_farm()
	var drop: Vector3 = _missions.call(&"dropoff_of", _missions.get(&"current"))
	var zone: Vector3 = _missions.get(&"zone")
	var cfg: Dictionary = _missions.get(&"config")
	var out := Vector2(drop.x - zone.x, drop.z - zone.z).length() - float(_missions.call(&"zone_radius"))
	assert_float(out).is_equal_approx(float(cfg["dropoff"]["outside"]), 0.5)
	# On the track's surface; the car beside it, off the way, facing the farm.
	assert_float(_voxels.heights.road_edge_distance(drop.x, drop.z)).is_equal(0.0)
	var car := _missions.get(&"_dropoff_car") as Node3D
	assert_float(_voxels.heights.road_edge_distance(car.global_position.x, car.global_position.z)).is_greater(0.0)
	var nose := car.global_basis.z
	assert_float(nose.dot((site["up"] as Vector3))).is_greater(0.99)
	# The group was set down there.
	var player := get_tree().get_nodes_in_group(&"players")[0] as Node3D
	assert_float(player.global_position.distance_to(drop)).is_less(10.0)


func test_every_site_on_the_map_sets_the_group_down_a_short_walk_outside_its_zone() -> void:
	var cfg: Dictionary = _missions.get(&"config")
	var sites: Array = _missions.get(&"sites")
	assert_int(sites.size()).is_greater(3)
	for i in sites.size():
		var site := MissionSites.describe(sites[i], i, cfg)
		var place := MissionSites.at_site(site, cfg)
		var drop: Vector3 = place["dropoff"]
		var centre: Vector3 = site["centre"]
		var out := Vector2(drop.x - centre.x, drop.z - centre.z).length() - MissionSites.zone_radius(site["footprint"], cfg)
		assert_float(out).override_failure_message("%s %d: %.1f m outside its zone" % [site["kind"], i, out]).is_between(0.0, MAX_WALK)


func test_a_mission_leaves_the_sites_own_pad_as_it_was() -> void:
	var sites: Array = _missions.get(&"sites")
	var before := {}
	for i in sites.size():
		before[i] = _pad_heights(sites[i]["footprint"])
	var site: Dictionary = await _ride_out_to_a_farm()
	var after := _pad_heights(site["footprint"])
	assert_array(after).is_equal(before[int(site["index"])])


func test_the_next_board_still_goes_to_sites() -> void:
	await _ride_out_to_a_farm()
	var player := get_tree().get_nodes_in_group(&"players")[0] as Node3D
	EventBus.publish(&"player.respawned", {"player": player})
	assert_str(str(_missions.get(&"state"))).is_equal("home")
	var offers: Array = _missions.get(&"offers")
	assert_bool(offers.any(func(o: Dictionary) -> bool: return not (o["site"] as Dictionary).is_empty())).is_true()


## The ground as it is now over `foot`, every 2 m.
func _pad_heights(foot: Rect2) -> Array:
	var out := []
	var x := foot.position.x
	while x <= foot.end.x:
		var z := foot.position.y
		while z <= foot.end.y:
			out.append(snappedf(_voxels.surface_height(x, z), 0.001))
			z += 2.0
		x += 2.0
	return out

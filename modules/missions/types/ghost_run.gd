extends MissionType
## Ghost Run: the drive waits in the innermost spot of the best-guarded building. No clock
## and no strike: guards hold their posts (more at the drive's building) until they spot or
## hear you, so you can sneak in or fight in. Riding home with the drive completes the job,
## as in Smash & Grab.

var _crate: Node3D
var _guards: Array[Node] = []


func server_open() -> void:
	var buildings: Array = missions.call(&"building_nodes")
	var zone: Vector3 = missions.get(&"zone")
	var rng: RandomNumberGenerator = missions.get(&"rng")
	var target := rng.randi_range(0, buildings.size() - 1) if not buildings.is_empty() else -1
	var at: Vector3 = (buildings[target] as MissionBuilding).inside(0.95, 0.0) if target >= 0 else zone
	_crate = missions.call(&"spawn_crate", at, [_item()])
	missions.call(&"fill_buildings_with_loot", [target])
	_place_guards(buildings, target, rng)
	status = {"delivered": false, "drive": _crate.global_position if _crate != null else at}
	changed()


func _item() -> String:
	return str(mission.get("objective_item", "usb_drive"))


## Every post at the drive's building is manned; the rest of the guards spread over the
## other buildings' posts.
func _place_guards(buildings: Array, target: int, rng: RandomNumberGenerator) -> void:
	var enemies := get_tree().get_first_node_in_group(&"enemies_api")
	if enemies == null:
		return
	var count := int(mission.get("guards", 6))
	var posts: Array = []
	var others: Array = []
	for i in buildings.size():
		var b := buildings[i] as MissionBuilding
		if i == target:
			posts.append_array(b.posts())
		else:
			others.append_array(b.posts())
	for i in range(others.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = others[i]
		others[i] = others[j]
		others[j] = t
	posts.append_array(others)
	for i in mini(count, posts.size()):
		var post: Dictionary = posts[i]
		_guards.append(enemies.call(&"server_spawn_guard", post["at"], float(post["yaw"]), []))


func server_done(riders: Array) -> bool:
	var inventory := get_tree().get_first_node_in_group(&"inventory_api")
	if inventory == null or bool(status.get("delivered", false)):
		return false
	for peer: int in riders:
		if int(inventory.call(&"count", peer, _item())) > 0:
			inventory.call(&"server_take", peer, _item())
			status["delivered"] = true
			changed()
			return true
	return false


func server_close() -> void:
	for g in _guards:
		if is_instance_valid(g) and not g.get_meta(&"dead", false):
			g.queue_free()
	_guards.clear()


func hud_lines(player: Node3D) -> Array[String]:
	if bool(status.get("delivered", false)):
		return ["Drive delivered"]
	var drive: Vector3 = status.get("drive", Vector3.ZERO)
	return ["Get the drive unseen if you can", "Drive %d m" % int(player.global_position.distance_to(drive))]


func markers() -> Array:
	if bool(status.get("delivered", false)) or not status.has("drive"):
		return []
	return [{"at": (status["drive"] as Vector3) + Vector3.UP * 2.2, "text": "DRIVE"}]

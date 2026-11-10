extends MissionType
## Clean Sweep: soldiers hold the zone's buildings: sentries at the doors, others inside,
## a couple patrolling between the buildings. The job is done when the last one is down;
## then ride home for the pay, and everything they carried is yours to loot. When only a
## few are left, markers show where they are.

## Markers show the last ones once this few are left.
const REVEAL_AT := 3
## How often the server re-sends the positions of the revealed ones, seconds.
const REVEAL_EVERY := 1.0

var _guards: Array[Node] = []
var _left := -1
var _reveal_in := 0.0


func server_open() -> void:
	missions.call(&"fill_buildings_with_loot", [])
	var enemies := get_tree().get_first_node_in_group(&"enemies_api")
	if enemies == null:
		status = {"left": 0, "total": 0}
		changed()
		return
	var rng: RandomNumberGenerator = missions.get(&"rng")
	var count := int(mission.get("guards", 6))
	var posts: Array = []
	for b: MissionBuilding in missions.call(&"building_nodes"):
		posts.append_array(b.posts())
	_shuffle(posts, rng)
	var patrols := mini(int(mission.get("patrols", 2)), count)
	for i in count - patrols:
		if posts.is_empty():
			break
		var post: Dictionary = posts.pop_back()
		_guards.append(enemies.call(&"server_spawn_guard", post["at"], float(post["yaw"]), []))
	for i in patrols:
		var route := _patrol_route(rng)
		_guards.append(enemies.call(&"server_spawn_guard", route[0], 0.0, route))
	_count()


## A loop through spots around the zone's buildings.
func _patrol_route(rng: RandomNumberGenerator) -> Array:
	var route := []
	var buildings: Array = missions.get(&"buildings")
	for i in 4:
		if buildings.is_empty():
			route.append(missions.call(&"random_spot", 0.6))
			continue
		var b: Dictionary = buildings[rng.randi_range(0, buildings.size() - 1)]
		var a := rng.randf() * TAU
		var r := float(b.get("radius", 4.0)) + 3.0
		var at := (b["position"] as Vector3) + Vector3(cos(a) * r, 0.0, sin(a) * r)
		at.y = float(missions.call(&"ground_y", at.x, at.z))
		route.append(at)
	return route


static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = list[i]
		list[i] = list[j]
		list[j] = t


func _alive() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for g in _guards:
		if is_instance_valid(g) and not g.get_meta(&"dead", false):
			out.append(g as Node3D)
	return out


## Server: counts who is left; tells everyone when it changed (and, near the end, where the
## last ones are).
func _count() -> void:
	var alive := _alive()
	var near_end := alive.size() <= REVEAL_AT
	if alive.size() == _left and not (near_end and _reveal_in <= 0.0):
		return
	if alive.size() != _left and alive.is_empty():
		EventBus.publish(&"missions.cleared", {"mission": mission.get("id", "")})
	_left = alive.size()
	_reveal_in = REVEAL_EVERY
	var spots := []
	if near_end:
		for g in alive:
			spots.append(g.global_position)
	status = {"left": _left, "total": _guards.size(), "spots": spots}
	changed()


func server_tick(delta: float) -> void:
	_reveal_in -= delta
	_count()


func server_done(_riders: Array) -> bool:
	return _alive().is_empty()


func server_close() -> void:
	for g in _alive():
		g.queue_free()
	_guards.clear()


func hud_lines(_player: Node3D) -> Array[String]:
	var left := int(status.get("left", -1))
	if left < 0:
		return []
	if left == 0:
		return ["Area clear: ride home"]
	return ["Guards left: %d of %d" % [left, int(status.get("total", left))]]


func markers() -> Array:
	var out := []
	for at: Vector3 in status.get("spots", []):
		out.append({"at": at + Vector3.UP * 2.3, "text": "TARGET"})
	return out

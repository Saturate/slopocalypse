class_name CityGarrison
extends Node
## Server: the city's guards (#220 step 3). Once every building stands, it puts guards on the
## spots `CityGuards` picks (windows, flat roofs, corners, patrol routes) through the enemies
## module's `enemies_api` group, so the city works without that module. A wiped-out garrison
## is put back after `refill_seconds` with no player within `refill_distance`, so nobody sees
## them appear.

## city.json's `guards` block.
var config: Dictionary = {}
var site: CitySite
var guards: Array[Node] = []

var _spawned := false
var _empty_for := 0.0
var _checks := 0


func _process(delta: float) -> void:
	if not multiplayer.is_server() or site == null or site.pending() > 0:
		return
	if not _spawned:
		_spawned = true
		server_spawn()
		return
	_check_refill(delta)


## Puts the garrison on its spots now; returns how many went up.
func server_spawn() -> int:
	var api := get_tree().get_first_node_in_group(&"enemies_api")
	if api == null or not api.has_method(&"server_spawn_guard"):
		return 0
	_checks += 1
	var spots := CityGuards.spots(site.plan, config, int(site.config.get("seed", 1)) + _checks)
	var where := site.global_transform
	guards.clear()
	for w: Dictionary in spots["windows"]:
		guards.append(api.call(&"server_spawn_guard", where * (w["at"] as Vector3), float(w["yaw"]) + where.basis.get_euler().y, []))
	for r: Dictionary in spots["roofs"]:
		var roof: Variant = _roof_under(where * (r["at"] as Vector3))
		if roof is Vector3:
			guards.append(api.call(&"server_spawn_guard", roof, float(r["yaw"]) + where.basis.get_euler().y, []))
	for c: Dictionary in spots["corners"]:
		guards.append(api.call(&"server_spawn_guard", where * (c["at"] as Vector3), float(c["yaw"]) + where.basis.get_euler().y, []))
	for route: Array in spots["routes"]:
		var points: Array = []
		for p: Vector3 in route:
			points.append(where * p)
		guards.append(api.call(&"server_spawn_guard", points[0], 0.0, points))
	guards = guards.filter(func(g: Variant) -> bool: return g is Node)
	return guards.size()


## The top of a flat roof near `eaves`: found by a ray from above, since the parapet and roof
## slab sit a little over the eaves.
func _roof_under(eaves: Vector3) -> Variant:
	var space := site.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eaves + Vector3.UP * 4.0, eaves + Vector3.DOWN * 1.0, PhysicsLayers.SOLID)
	var hit := space.intersect_ray(query)
	return (hit["position"] as Vector3) + Vector3.UP * 0.05 if not hit.is_empty() else null


func alive() -> int:
	var n := 0
	for g in guards:
		if is_instance_valid(g) and not g.get_meta(&"dead", false):
			n += 1
	return n


func _check_refill(delta: float) -> void:
	if alive() > 0:
		_empty_for = 0.0
		return
	var reach := float(config.get("refill_distance", 150.0))
	for p: Node in get_tree().get_nodes_in_group(&"players"):
		if p is Node3D and (p as Node3D).global_position.distance_to(site.global_position) < reach:
			_empty_for = 0.0
			return
	_empty_for += delta
	if _empty_for >= float(config.get("refill_seconds", 600.0)):
		_empty_for = 0.0
		server_spawn()

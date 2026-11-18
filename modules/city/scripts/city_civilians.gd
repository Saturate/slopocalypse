class_name CityCivilians
extends Node
## Server: the people living in the city (#342). Each building near a player (within
## `spawn_distance` of its door) gets 0 to `per_building` civilians at its door, up to
## `max_alive` in the city; they run to that building's or a neighbour's door when shooting
## starts (CivilianBrain). When no player is within `despawn_distance`, the building's
## living civilians go and it may be filled again later. Through the enemies module's
## `enemies_api`, so the city works without it.

## city.json's `civilians` block.
var config: Dictionary = {}
var site: CitySite

## Building index -> its civilians (nodes).
var _homes: Dictionary[int, Array] = {}
var _check_in := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = int(config.get("seed", 1))


func _process(delta: float) -> void:
	if not multiplayer.is_server() or site == null or site.pending() > 0:
		return
	_check_in -= delta
	if _check_in > 0.0:
		return
	_check_in = float(config.get("check_seconds", 2.0))
	server_update(_player_spots())


## Fills buildings near `players` (world positions) and empties those far from all of them.
func server_update(players: Array[Vector3]) -> void:
	var api := get_tree().get_first_node_in_group(&"enemies_api")
	if api == null or not api.has_method(&"server_spawn_civilian"):
		return
	var buildings: Array = site.plan["buildings"]
	var near := float(config.get("spawn_distance", 120.0))
	var far := float(config.get("despawn_distance", 200.0))
	for i in buildings.size():
		var door := door_of(buildings[i])
		var closest := INF
		for p: Vector3 in players:
			closest = minf(closest, p.distance_to(door))
		if _homes.has(i):
			if closest > far:
				for person: Variant in _homes[i]:
					if is_instance_valid(person) and not (person as Node).get_meta(&"dead", false):
						(person as Node).queue_free()
				_homes.erase(i)
		elif closest < near and alive() < int(config.get("max_alive", 60)):
			_fill(api, i, buildings)


func _fill(api: Node, i: int, buildings: Array) -> void:
	var counts: Array = config.get("per_building", [0, 3])
	var want := mini(_rng.randi_range(int(counts[0]), int(counts[1])), int(config.get("max_alive", 60)) - alive())
	var people: Array = []
	var refuges := _refuges_near(i, buildings)
	var door := door_of(buildings[i])
	for k in want:
		# A step or two out from the door, on the pavement, spread a little.
		var at := door + Vector3(_rng.randf_range(-2.0, 2.0), 0.0, _rng.randf_range(-2.0, 2.0))
		people.append(api.call(&"server_spawn_civilian", at, _rng.randf() * TAU, refuges))
	_homes[i] = people


## Building `b`'s first door, in the world.
func door_of(b: Dictionary) -> Vector3:
	var d: Vector2 = b["door_out"]
	return _where() * Vector3(d.x, CitySite.KERB, d.y)


## Every door of building `i` and of buildings whose doors are within `refuge_distance`.
func _refuges_near(i: int, buildings: Array) -> Array:
	var reach := float(config.get("refuge_distance", 40.0))
	var home := door_of(buildings[i])
	var out: Array = []
	for b: Dictionary in buildings:
		for d: Vector2 in b["doors"]:
			var at := _where() * Vector3(d.x, CitySite.KERB, d.y)
			if at.distance_to(home) <= reach:
				out.append(at)
	return out


## The city's place in the world (its own transform when it isn't in a tree, as in tests).
func _where() -> Transform3D:
	return site.global_transform if site.is_inside_tree() else site.transform


func alive() -> int:
	var n := 0
	for people: Array in _homes.values():
		for person: Variant in people:
			if is_instance_valid(person) and not (person as Node).get_meta(&"dead", false):
				n += 1
	return n


func _player_spots() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p: Node in get_tree().get_nodes_in_group(&"players"):
		if p is Node3D:
			out.append((p as Node3D).global_position)
	return out

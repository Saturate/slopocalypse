class_name SmokeField
extends Node
## Server: the smoke in the world as simple spheres, so soldiers can test their sight against
## it. Blasts start plumes (their `kind` picks the entry in `sources`); at most `max_volumes`
## live at once and the oldest goes first. Clients get one `smoke.spawned` per plume and
## advance it themselves, plus `smoke.ended` when one goes.
##
## Sits in the `sight_blockers` group: anything checking a line of sight asks
## `sight_blocked(from, to)` without knowing this module exists.

var config: Dictionary = {}
var volumes: Array[SmokeVolume] = []
var _next_id := 1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"sight_blockers")
	EventBus.subscribe(&"explosion", _on_explosion)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"explosion", _on_explosion)


func _process(delta: float) -> void:
	if volumes.is_empty():
		return
	var t := Prof.start()
	advance(delta)
	Prof.stop(&"smoke/field", t)


func advance(delta: float) -> void:
	var gone: Array[SmokeVolume] = []
	for v in volumes:
		v.age += delta
		if v.ended():
			gone.append(v)
	for v in gone:
		_end(v)


func _on_explosion(p: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	server_spawn(str(p.get("kind", "blast")), p["position"])


func server_spawn(source: String, at: Vector3) -> SmokeVolume:
	var sources: Dictionary = config["sources"]
	var entry: Dictionary = sources.get(source, sources["blast"])
	while volumes.size() >= int(config["max_volumes"]):
		_end(volumes[0])
	var wind: Array = config["wind"]
	var v := SmokeVolume.new()
	v.id = _next_id
	_next_id += 1
	v.source = source if sources.has(source) else "blast"
	v.origin = at
	v.r0 = float(entry["r0"])
	v.r1 = float(entry["r1"])
	v.grow = float(entry["grow_seconds"])
	v.lifetime = float(entry["lifetime"])
	v.density = float(entry["density"])
	v.wind = Vector3(float(wind[0]), 0.0, float(wind[1]))
	v.rise = float(config["rise_speed"])
	v.seed = _rng.randi()
	volumes.append(v)
	Net.server_broadcast(&"smoke.spawned", v.to_payload())
	return v


func _end(v: SmokeVolume) -> void:
	volumes.erase(v)
	Net.server_broadcast(&"smoke.ended", {"id": v.id})


## Whether the smoke between two points is thick enough to hide one from the other.
func sight_blocked(from: Vector3, to: Vector3) -> bool:
	var total := 0.0
	for v in volumes:
		total += v.along(from, to)
	return total > float(config["sight_block"])

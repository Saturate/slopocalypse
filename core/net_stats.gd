class_name NetStats
extends RefCounted
## What the server sends, by source, so the perf log can say what the network is spent on.
## Godot reports only total bytes per connection outside its editor debugger, so these are
## estimates from payload sizes (`var_to_bytes`) times recipients; the perf module puts them
## next to ENet's exact total, and what the estimates don't cover shows as `other`.
## Static, like `Prof`, so any script can count without depending on the perf module:
##     NetStats.add(&"event/missions.voxel_edits", bytes * peers)

static var _bytes: Dictionary[StringName, int] = {}


static func add(source: StringName, bytes: int) -> void:
	_bytes[source] = _bytes.get(source, 0) + bytes


## Bytes `payload` (one RPC's arguments) takes on the wire, near enough.
static func size_of(payload: Variant) -> int:
	return var_to_bytes(payload).size()


## {source: bytes} since the last call, then starts again.
static func take() -> Dictionary:
	var out := {}
	for source: StringName in _bytes:
		out[String(source)] = _bytes[source]
	_bytes.clear()
	return out

extends Node
## Wires: power lines, barbed wire and cables hung between pairs of points, sagging under
## their own weight.
##
## Other modules hand over sets of spans under an owner key and can replace or drop a set
## later. Every machine is told the same spans from the same seed, so nothing is sent:
##   EventBus.publish(&"wires.set", {"owner": "fence/12", "spans": [{"from": Vector3, "to": Vector3,
##       "kind": &"barbed"}, ...]})   (replaces that owner's set; optional "sag" per span
##       overrides the kind's, as a share of the span's length)
##   EventBus.publish(&"wires.clear", {"owner": "fence/12"})
##
## Spans are cut into pieces no longer than a chunk and drawn as one mesh per chunk and
## detail step, with visibility ranges picking the step by distance. Each (chunk, step) mesh
## is a unit of work: its arrays are built on worker threads and only the mesh and node are
## made here, a few each frame within `build_ms_per_frame`. `flush()` builds everything at
## once. A headless process keeps the spans and builds no meshes.

const CONFIG := "res://modules/wires/data/wires.json"
const SHADER := preload("res://modules/wires/shaders/wire.gdshader")
const REQUIRED := {
	"chunk_size": TYPE_FLOAT, "max_span": TYPE_FLOAT, "sides": TYPE_FLOAT, "min_pixels": TYPE_FLOAT,
	"roughness": TYPE_FLOAT, "build_ms_per_frame": TYPE_FLOAT, "fade": TYPE_FLOAT, "lod": TYPE_ARRAY,
	"kinds": TYPE_DICTIONARY,
}
const KIND_REQUIRED := {"thickness": TYPE_FLOAT, "colour": TYPE_ARRAY, "sag": TYPE_FLOAT, "segment_length": TYPE_FLOAT}

var config: Dictionary = {}
## Whether meshes are built; off on a headless server. Tests turn it on before adding the node.
var visual := DisplayServer.get_name() != "headless"
## Slowest single unit of work so far, in microseconds: building one (chunk, step)'s arrays
## (worker thread) and turning them into a mesh and node (this thread).
var slowest_build_usec := 0
var slowest_apply_usec := 0
## Most time this thread spent on wires in one frame.
var slowest_frame_usec := 0

var _kinds: Dictionary[StringName, Dictionary] = {}
var _material: ShaderMaterial
var _chunk_size := 32.0
var _max_span := 400.0
var _sides := 4
var _fade := 0.0
## Owner -> chunk -> pieces of that owner's spans in the chunk.
var _owners: Dictionary[String, Dictionary] = {}
var _span_counts: Dictionary[String, int] = {}
## Chunk -> owners with pieces in it.
var _chunk_owners: Dictionary[Vector2i, Dictionary] = {}
var _chunks: Dictionary[Vector2i, Node3D] = {}
## Chunks whose spans changed and whose units are not started yet.
var _dirty: Dictionary[Vector2i, bool] = {}
## Bumped each time a chunk changes, so units started before a change are thrown away.
var _generation: Dictionary[Vector2i, int] = {}
## Started units: {task (-1 when built here), unit}. A unit ({key, step, generation, origin,
## begin, until, then arrays and usec}) belongs to its worker until the task is done, so
## nothing here reads or writes it before that.
var _pending: Array[Dictionary] = []
var _budget_usec := 2000


## How far from the centre of its mesh's box a wire piece can reach across the ground: half
## a chunk's diagonal, plus up to half a piece hanging out past the chunk's edge (a piece is
## filed under the chunk its middle is in). Godot measures visibility ranges to that centre,
## so a detail step must reach at least this far past the camera to cover the wire nearest it.
static func reach(chunk_size: float) -> float:
	return chunk_size * (sqrt(0.5) + 0.5)


func _ready() -> void:
	set_process(false)
	var data: Variant = Data.load_json(CONFIG)
	if not (data is Dictionary and Data.require(CONFIG, data, REQUIRED)):
		return
	config = data
	_chunk_size = maxf(float(config["chunk_size"]), 1.0)
	_max_span = float(config["max_span"])
	_sides = maxi(int(config["sides"]), 3)
	_fade = maxf(float(config["fade"]), 0.0)
	_budget_usec = int(float(config["build_ms_per_frame"]) * 1000.0)
	for id: String in config["kinds"]:
		var k := _kind_from(id, config["kinds"][id])
		if not k.is_empty():
			_kinds[StringName(id)] = k
	if visual:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter(&"min_pixels", float(config["min_pixels"]))
		_material.set_shader_parameter(&"roughness", float(config["roughness"]))
		_material.set_shader_parameter(&"sides", float(_sides))
	EventBus.subscribe(&"wires.set", _on_set)
	EventBus.subscribe(&"wires.clear", _on_clear)


## A kind's data checked and readied for drawing, or empty (logged) when it is unusable.
func _kind_from(id: String, kind: Variant) -> Dictionary:
	var where := "%s kinds.%s" % [CONFIG, id]
	if not (kind is Dictionary and Data.require(where, kind, KIND_REQUIRED)):
		return {}
	var k: Dictionary = (kind as Dictionary).duplicate()
	var c: Array = k["colour"]
	if c.size() < 3 or not (c[0] is float and c[1] is float and c[2] is float):
		Log.error(&"wires", "%s: colour should be [r, g, b]" % where)
		return {}
	if k.has("barbs") and not k["barbs"] is Dictionary:
		Log.error(&"wires", "%s: barbs should be an object" % where)
		return {}
	if float(k["thickness"]) <= 0.0 or float(k["segment_length"]) <= 0.0:
		Log.error(&"wires", "%s: thickness and segment_length should be above 0" % where)
		return {}
	k["color"] = Color(float(c[0]), float(c[1]), float(c[2])).srgb_to_linear()
	k["radius"] = float(k["thickness"]) * 0.5
	return k


func _exit_tree() -> void:
	EventBus.unsubscribe(&"wires.set", _on_set)
	EventBus.unsubscribe(&"wires.clear", _on_clear)
	for entry in _pending:
		_wait(entry)
	_pending.clear()


func _wait(entry: Dictionary) -> void:
	if int(entry["task"]) >= 0:
		WorkerThreadPool.wait_for_task_completion(int(entry["task"]))


func _process(_delta: float) -> void:
	var prof := Prof.start()
	var until := prof + _budget_usec
	# Starting a chunk is cheap (its pieces are gathered and handed to the workers), but a
	# thousand at once is not, so they share the budget too.
	for key: Vector2i in _dirty.keys():
		_dirty.erase(key)
		_start(key, true)
		if Time.get_ticks_usec() >= until:
			break
	var i := 0
	while i < _pending.size():
		var entry := _pending[i]
		var task := int(entry["task"])
		if task >= 0 and not WorkerThreadPool.is_task_completed(task):
			i += 1
			continue
		_wait(entry)
		_pending.remove_at(i)
		_apply(entry["unit"])
		if Time.get_ticks_usec() >= until:
			break
	if _pending.is_empty() and _dirty.is_empty():
		set_process(false)
	slowest_frame_usec = maxi(slowest_frame_usec, Time.get_ticks_usec() - prof)
	Prof.stop(&"wires/build", prof)


## Builds every changed chunk now, on this thread, instead of over the next frames.
func flush() -> void:
	for key: Vector2i in _dirty.keys():
		_start(key, false)
	_dirty.clear()
	for entry in _pending:
		_wait(entry)
		_apply(entry["unit"])
	_pending.clear()
	set_process(false)


func _on_set(p: Dictionary) -> void:
	var spans: Array = p.get("spans", [])
	set_spans(str(p.get("owner", "")), spans)


func _on_clear(p: Dictionary) -> void:
	clear(str(p.get("owner", "")))


func has_kind(kind: StringName) -> bool:
	return _kinds.has(kind)


## Replaces everything `owner` has hung with `spans` ({from, to, kind, sag?} each). Spans
## whose ends coincide are skipped; malformed ones are refused and logged.
func set_spans(owner: String, spans: Array) -> void:
	if owner.is_empty():
		Log.error(&"wires", "wires need an owner, so they can be replaced or removed later")
		return
	var dirty := _drop(owner)
	var by_chunk: Dictionary[Vector2i, Array] = {}
	var count := 0
	for span: Variant in spans:
		var checked := _check(owner, span)
		if checked.is_empty():
			continue
		var a: Vector3 = checked["from"]
		var b: Vector3 = checked["to"]
		var k: Dictionary = checked["kind"]
		var sag := WireCurve.sag_for(a, b, float(checked["sag"]))
		var pieces := ceili(a.distance_to(b) / _chunk_size)
		for i in pieces:
			var t0 := float(i) / float(pieces)
			var t1 := float(i + 1) / float(pieces)
			var key := _chunk_of(WireCurve.point_at(a, b, sag, (t0 + t1) * 0.5))
			if not by_chunk.has(key):
				by_chunk[key] = []
			by_chunk[key].append({"a": a, "b": b, "sag": sag, "t0": t0, "t1": t1, "kind": k})
		count += 1
	if count > 0:
		_owners[owner] = by_chunk
		_span_counts[owner] = count
		for key: Vector2i in by_chunk:
			if not _chunk_owners.has(key):
				_chunk_owners[key] = {}
			_chunk_owners[key][owner] = true
			dirty[key] = true
	_mark(dirty)


## {from, to, kind (its data), sag (share)} for a usable span, or empty after logging why.
## Non-finite ends would make the piece count undefined (an endless loop on some CPUs).
func _check(owner: String, span: Variant) -> Dictionary:
	if not (span is Dictionary and span.get("from") is Vector3 and span.get("to") is Vector3):
		Log.error(&"wires", "%s: a span needs Vector3 `from` and `to`" % owner)
		return {}
	var a: Vector3 = span["from"]
	var b: Vector3 = span["to"]
	if not (a.is_finite() and b.is_finite()):
		Log.error(&"wires", "%s: a span's ends must be finite, got %s and %s" % [owner, a, b])
		return {}
	var kind := StringName(str(span.get("kind", "")))
	if not _kinds.has(kind):
		Log.error(&"wires", "%s: no wire kind '%s'" % [owner, kind])
		return {}
	var length := a.distance_to(b)
	if length < 0.01:
		return {}
	if length > _max_span:
		Log.error(&"wires", "%s: a %.0f m span is longer than max_span (%.0f m)" % [owner, length, _max_span])
		return {}
	var k: Dictionary = _kinds[kind]
	var sag: Variant = span.get("sag", k["sag"])
	if not ((sag is float or sag is int) and is_finite(float(sag))):
		Log.error(&"wires", "%s: a span's sag must be a finite number, got %s" % [owner, sag])
		return {}
	return {"from": a, "to": b, "kind": k, "sag": float(sag)}


func clear(owner: String) -> void:
	_mark(_drop(owner))


## Spans hung by `owner`, or by everyone when it is empty.
func span_count(owner: String = "") -> int:
	if owner.is_empty():
		var total := 0
		for n: int in _span_counts.values():
			total += n
		return total
	return _span_counts.get(owner, 0)


## The chunk nodes drawing wires now (none on a headless server).
func chunk_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	out.assign(_chunks.values())
	return out


## Forgets `owner`'s spans; returns the chunks they were in.
func _drop(owner: String) -> Dictionary:
	var dirty := {}
	if not _owners.has(owner):
		return dirty
	for key: Vector2i in _owners[owner]:
		dirty[key] = true
		var owners: Dictionary = _chunk_owners.get(key, {})
		owners.erase(owner)
		if owners.is_empty():
			_chunk_owners.erase(key)
	_owners.erase(owner)
	_span_counts.erase(owner)
	return dirty


func _chunk_of(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / _chunk_size), floori(point.z / _chunk_size))


func _mark(dirty: Dictionary) -> void:
	if not visual or dirty.is_empty():
		return
	for key: Vector2i in dirty:
		_dirty[key] = true
		_generation[key] = _generation.get(key, 0) + 1
	set_process(true)


## Queues a unit per detail step for `key`, on worker threads when `threaded`. A chunk left
## with no wires goes at once.
func _start(key: Vector2i, threaded: bool) -> void:
	if not _chunk_owners.has(key):
		var old: Node3D = _chunks.get(key)
		if old != null:
			remove_child(old)
			old.free()
			_chunks.erase(key)
		return
	var pieces: Array = []
	var low := INF
	var high := -INF
	for owner: String in _chunk_owners[key]:
		for piece: Dictionary in _owners[owner].get(key, []):
			pieces.append(piece)
			var mid := WireCurve.point_at(piece["a"], piece["b"], piece["sag"], (float(piece["t0"]) + float(piece["t1"])) * 0.5)
			low = minf(low, mid.y)
			high = maxf(high, mid.y)
	var origin := Vector3((float(key.x) + 0.5) * _chunk_size, (low + high) * 0.5, (float(key.y) + 0.5) * _chunk_size)
	var steps: Array = config["lod"]
	var begin := 0.0
	for i in steps.size():
		var until := float((steps[i] as Dictionary).get("until", 0.0))
		var unit := {"key": key, "step": i, "generation": _generation.get(key, 0), "origin": origin, "begin": begin, "until": until}
		var task := -1
		if threaded:
			task = WorkerThreadPool.add_task(WireMesh.fill.bind(unit, pieces, steps, _sides))
		else:
			WireMesh.fill(unit, pieces, steps, _sides)
		_pending.append({"task": task, "unit": unit})
		begin = until


## Turns a finished unit into its step's mesh, replacing the one it had.
func _apply(unit: Dictionary) -> void:
	var key: Vector2i = unit["key"]
	slowest_build_usec = maxi(slowest_build_usec, int(unit.get("usec", 0)))
	if int(unit["generation"]) != _generation.get(key, 0) or not _chunk_owners.has(key):
		return
	var started := Time.get_ticks_usec()
	var chunk: Node3D = _chunks.get(key)
	if chunk == null:
		chunk = Node3D.new()
		chunk.name = "Chunk_%d_%d" % [key.x, key.y]
		add_child(chunk)
		_chunks[key] = chunk
	var step := int(unit["step"])
	var old := chunk.get_node_or_null("Step%d" % step)
	if old != null:
		chunk.remove_child(old)
		old.free()
	var arrays: Array = unit.get("arrays", [])
	if not arrays.is_empty():
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _material)
		var inst := MeshInstance3D.new()
		inst.name = "Step%d" % step
		inst.mesh = mesh
		inst.position = unit["origin"]
		# Thinner than a shadow texel; they would cost a shadow pass and show as noise.
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Godot measures these to the centre of the mesh's box (transformed_aabb in
		# renderer_scene_cull.cpp), which is why the data's steps reach past `reach()`.
		inst.visibility_range_begin = float(unit["begin"])
		inst.visibility_range_end = float(unit["until"])
		inst.visibility_range_begin_margin = _fade if float(unit["begin"]) > 0.0 else 0.0
		inst.visibility_range_end_margin = _fade
		inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		chunk.add_child(inst)
	slowest_apply_usec = maxi(slowest_apply_usec, Time.get_ticks_usec() - started)

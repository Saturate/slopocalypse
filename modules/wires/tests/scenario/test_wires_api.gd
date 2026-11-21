extends GdUnitTestSuite
## Other modules hang wires through `wires.set` and `wires.clear`: the spans are drawn in
## chunk meshes, an owner's new set replaces only its own spans, and a headless process
## keeps the spans but builds nothing to draw.

const MODULE := "res://modules/wires/wires_module.gd"


func _module(visual: bool) -> Node:
	var module: Node = auto_free((load(MODULE) as GDScript).new())
	module.set(&"visual", visual)
	add_child(module)
	return module


## Publishes and then builds what changed now, instead of over the next frames.
func _publish(module: Node, topic: StringName, payload: Dictionary) -> void:
	EventBus.publish(topic, payload)
	module.call(&"flush")


func _fence(origin: Vector3, posts: int, kind: StringName) -> Array:
	var spans := []
	for i in posts - 1:
		spans.append({"from": origin + Vector3(float(i) * 3.0, 1.2, 0), "to": origin + Vector3(float(i + 1) * 3.0, 1.2, 0), "kind": kind})
	return spans


func _meshes(module: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for chunk: Node in module.call(&"chunk_nodes"):
		for child in chunk.get_children():
			if child is MeshInstance3D:
				out.append(child)
	return out


func _vertex_count(module: Node) -> int:
	var total := 0
	for inst in _meshes(module):
		total += (inst.mesh as ArrayMesh).surface_get_array_len(0)
	return total


func test_spans_are_built_into_chunk_meshes() -> void:
	var module := _module(true)
	_publish(module, &"wires.set", {"owner": "fence", "spans": _fence(Vector3(4, 0, 4), 6, &"barbed")})
	assert_int(module.call(&"span_count", "fence")).is_equal(5)
	# Fifteen metres of fence sit in one chunk: one node, a mesh per detail step.
	var chunks: Array = module.call(&"chunk_nodes")
	assert_int(chunks.size()).is_equal(1)
	var meshes := _meshes(module)
	var steps: Array = (module.get(&"config") as Dictionary)["lod"]
	assert_int(meshes.size()).is_equal(steps.size())
	for inst in meshes:
		assert_int(inst.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert_int(inst.get_child_count()).is_equal(0)
	# Each step starts where the last stopped, and the near one has the most to draw.
	for i in range(1, meshes.size()):
		assert_float(meshes[i].visibility_range_begin).is_equal(meshes[i - 1].visibility_range_end)
		assert_int((meshes[i].mesh as ArrayMesh).surface_get_array_len(0)).is_less((meshes[0].mesh as ArrayMesh).surface_get_array_len(0))


func test_replacing_an_owner_replaces_only_its_spans() -> void:
	var module := _module(true)
	var fence_spans := _fence(Vector3(4, 0, 4), 6, &"barbed")
	_publish(module, &"wires.set", {"owner": "fence", "spans": fence_spans})
	_publish(module, &"wires.set", {"owner": "line", "spans": [{"from": Vector3(0, 9, 0), "to": Vector3(200, 9, 10), "kind": &"high_voltage"}]})
	assert_int(module.call(&"span_count")).is_equal(6)
	var both := _vertex_count(module)
	_publish(module, &"wires.set", {"owner": "line", "spans": [
		{"from": Vector3(0, 9, 0), "to": Vector3(200, 9, 10), "kind": &"high_voltage"},
		{"from": Vector3(0, 9, 2), "to": Vector3(200, 9, 12), "kind": &"high_voltage"}]})
	assert_int(module.call(&"span_count", "line")).is_equal(2)
	assert_int(module.call(&"span_count", "fence")).is_equal(5)
	assert_int(_vertex_count(module)).is_greater(both)
	_publish(module, &"wires.clear", {"owner": "line"})
	assert_int(module.call(&"span_count", "line")).is_equal(0)
	assert_int(module.call(&"span_count", "fence")).is_equal(5)
	# What is left is exactly the fence as it was drawn alone.
	var alone := _module(true)
	alone.call(&"set_spans", "fence", fence_spans)
	alone.call(&"flush")
	assert_int(_vertex_count(module)).is_equal(_vertex_count(alone))
	assert_int((module.call(&"chunk_nodes") as Array).size()).is_equal(1)
	_publish(module, &"wires.clear", {"owner": "fence"})
	assert_int((module.call(&"chunk_nodes") as Array).size()).is_equal(0)
	assert_int(module.get_child_count()).is_equal(0)


func test_a_long_span_is_cut_into_pieces_across_chunks() -> void:
	var module := _module(true)
	var chunk_size := float((module.get(&"config") as Dictionary)["chunk_size"])
	# Ten chunks long exactly, so each piece's middle is in its own chunk.
	var length := chunk_size * 10.0
	module.call(&"set_spans", "line", [{"from": Vector3(0, 20, 0), "to": Vector3(length, 20, 0), "kind": &"high_voltage"}])
	module.call(&"flush")
	assert_int((module.call(&"chunk_nodes") as Array).size()).is_equal(10)


func test_a_span_across_zero_lands_in_negative_chunks() -> void:
	var module := _module(true)
	var chunk_size := float((module.get(&"config") as Dictionary)["chunk_size"])
	# Two pieces: one middle at x = -0.75 chunk, one at +0.25; both just below z = 0.
	var from := Vector3(-chunk_size * 1.25, 5, -3)
	var to := Vector3(chunk_size * 0.75, 5, -3)
	module.call(&"set_spans", "line", [{"from": from, "to": to, "kind": &"low_voltage"}])
	module.call(&"flush")
	var names: Array[String] = []
	for chunk in module.call(&"chunk_nodes") as Array[Node3D]:
		names.append(String(chunk.name))
		# Each chunk's meshes stand in that chunk, wherever its key's sign.
		var near := chunk.get_node("Step0") as MeshInstance3D
		var centre := near.position + near.get_aabb().get_center()
		assert_float(centre.x).is_between(from.x, to.x)
	names.sort()
	assert_array(names).is_equal(["Chunk_-1_-1", "Chunk_0_-1"])


func test_a_diagonal_span_can_put_two_pieces_in_one_chunk() -> void:
	var module := _module(true)
	var chunk_size := float((module.get(&"config") as Dictionary)["chunk_size"])
	# Just over a chunk long, so two pieces, both of whose middles fall in chunk (0, 0).
	var side := chunk_size * 0.74
	module.call(&"set_spans", "guy", [{"from": Vector3(1, 6, 1), "to": Vector3(1 + side, 0.5, 1 + side), "kind": &"steel_cable"}])
	module.call(&"flush")
	var chunks: Array = module.call(&"chunk_nodes")
	assert_int(chunks.size()).is_equal(1)
	var near := (chunks[0] as Node3D).get_node("Step0") as MeshInstance3D
	# Both pieces are in the one mesh: it runs the whole span.
	assert_float(near.get_aabb().size.x).is_greater(side - 0.5)


func test_built_over_the_next_frames_on_worker_threads() -> void:
	var module := _module(true)
	module.call(&"set_spans", "fence", _fence(Vector3(4, 0, 4), 6, &"barbed"))
	assert_int((module.call(&"chunk_nodes") as Array).size()).is_equal(0)
	assert_bool(module.is_processing()).is_true()
	for i in 60:
		if not module.is_processing():
			break
		await await_idle_frame()
	assert_bool(module.is_processing()).is_false()
	var steps: Array = (module.get(&"config") as Dictionary)["lod"]
	assert_int(_meshes(module).size()).is_equal(steps.size())
	# The same as building it all at once.
	var at_once := _module(true)
	at_once.call(&"set_spans", "fence", _fence(Vector3(4, 0, 4), 6, &"barbed"))
	at_once.call(&"flush")
	assert_int(_vertex_count(module)).is_equal(_vertex_count(at_once))


func test_a_change_while_building_wins() -> void:
	var module := _module(true)
	module.call(&"set_spans", "fence", _fence(Vector3(4, 0, 4), 6, &"barbed"))
	await await_idle_frame()
	module.call(&"set_spans", "fence", _fence(Vector3(4, 0, 4), 3, &"barbed"))
	for i in 60:
		if not module.is_processing():
			break
		await await_idle_frame()
	var at_once := _module(true)
	at_once.call(&"set_spans", "fence", _fence(Vector3(4, 0, 4), 3, &"barbed"))
	at_once.call(&"flush")
	assert_int(_vertex_count(module)).is_equal(_vertex_count(at_once))


func test_a_headless_run_builds_nothing_visual() -> void:
	var module := _module(false)
	_publish(module, &"wires.set", {"owner": "fence", "spans": _fence(Vector3.ZERO, 4, &"barbed")})
	assert_int(module.call(&"span_count", "fence")).is_equal(3)
	assert_int((module.call(&"chunk_nodes") as Array).size()).is_equal(0)
	assert_int(module.get_child_count()).is_equal(0)
	# The gate runs headless, so the module's own default is off here too.
	var fresh: Node = auto_free((load(MODULE) as GDScript).new())
	assert_bool(bool(fresh.get(&"visual"))).is_false()


func test_unknown_kinds_are_refused_by_name() -> void:
	var module := _module(true)
	Log.begin_capture()
	module.call(&"set_spans", "odd", [{"from": Vector3.ZERO, "to": Vector3(5, 0, 0), "kind": &"spaghetti"}])
	var entries := Log.end_capture()
	assert_str(LogCapture.text(entries)).contains("spaghetti")
	assert_int(module.call(&"span_count", "odd")).is_equal(0)


func test_bad_spans_are_refused() -> void:
	var module := _module(true)
	var max_span := float((module.get(&"config") as Dictionary)["max_span"])
	# Ends in the same place: nothing to hang, skipped quietly.
	module.call(&"set_spans", "same", [{"from": Vector3(3, 2, 1), "to": Vector3(3, 2, 1), "kind": &"barbed"}])
	assert_int(module.call(&"span_count", "same")).is_equal(0)
	Log.begin_capture()
	module.call(&"set_spans", "nan", [{"from": Vector3(NAN, 0, 0), "to": Vector3(5, 0, 0), "kind": &"barbed"}])
	module.call(&"set_spans", "inf", [{"from": Vector3.ZERO, "to": Vector3(INF, 0, 0), "kind": &"barbed"}])
	module.call(&"set_spans", "long", [{"from": Vector3.ZERO, "to": Vector3(max_span + 1.0, 0, 0), "kind": &"high_voltage"}])
	module.call(&"set_spans", "sag", [{"from": Vector3.ZERO, "to": Vector3(5, 0, 0), "kind": &"barbed", "sag": NAN}])
	module.call(&"set_spans", "", [{"from": Vector3.ZERO, "to": Vector3(5, 0, 0), "kind": &"barbed"}])
	var text := LogCapture.text(Log.end_capture())
	for owner in ["nan", "inf", "long", "sag"]:
		assert_int(module.call(&"span_count", owner)).is_equal(0)
		assert_str(text).contains("%s:" % owner)
	assert_str(text).contains("max_span")
	assert_str(text).contains("owner")
	assert_int(module.call(&"span_count")).is_equal(0)
	module.call(&"flush")
	assert_int((module.call(&"chunk_nodes") as Array).size()).is_equal(0)


func test_detail_steps_reach_past_the_farthest_wire_in_a_chunk() -> void:
	var module := _module(true)
	var config: Dictionary = module.get(&"config")
	var reach: float = (load(MODULE) as GDScript).call(&"reach", float(config["chunk_size"]))
	for step: Dictionary in config["lod"]:
		assert_float(float(step["until"]) - float(config["fade"])).is_greater_equal(reach)


func test_every_kind_in_the_data_is_drawn() -> void:
	var module := _module(true)
	var kinds: Dictionary = (module.get(&"config") as Dictionary)["kinds"]
	assert_int(kinds.size()).is_greater_equal(4)
	for kind: String in kinds:
		assert_bool(module.call(&"has_kind", StringName(kind))).is_true()
		var alone := _module(true)
		alone.call(&"set_spans", kind, [{"from": Vector3.ZERO, "to": Vector3(20, 0, 0), "kind": StringName(kind)}])
		alone.call(&"flush")
		assert_int(alone.call(&"span_count", kind)).is_equal(1)
		assert_int(_vertex_count(alone)).is_greater(0)

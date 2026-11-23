extends GdUnitTestSuite
## The debug API's request handling without sockets: HTTP parsing, the token, and the
## methods that read and change the tree.


func _request(body: String, token: String = "t0k") -> PackedByteArray:
	var head := "POST /rpc HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n" % [token, body.to_utf8_buffer().size()]
	return (head + body).to_utf8_buffer()


func _handler() -> DebugHandler:
	var h := DebugHandler.new()
	h.token = "t0k"
	h.role = "client"
	return h


func test_a_request_is_incomplete_until_the_whole_body_arrives() -> void:
	var data := _request("{\"method\": \"ping\"}")
	assert_bool(DebugHandler.parse_request(data.slice(0, 20))["complete"]).is_false()
	assert_bool(DebugHandler.parse_request(data.slice(0, data.size() - 3))["complete"]).is_false()
	var full := DebugHandler.parse_request(data)
	assert_bool(full["complete"]).is_true()
	assert_str(full["body"]).is_equal("{\"method\": \"ping\"}")
	assert_str(full["headers"]["authorization"]).is_equal("Bearer t0k")


func test_the_token_is_required() -> void:
	var reply := _handler().respond(DebugHandler.parse_request(_request("{\"method\": \"ping\"}", "wrong")), get_tree())
	assert_int(int(reply[0])).is_equal(401)
	reply = _handler().respond(DebugHandler.parse_request(_request("{\"method\": \"ping\"}")), get_tree())
	assert_int(int(reply[0])).is_equal(200)
	assert_int(int(reply[1]["result"]["pid"])).is_equal(OS.get_process_id())


func test_bad_bodies_and_unknown_methods_say_what_is_wrong() -> void:
	assert_int(int(_handler().respond(DebugHandler.parse_request(_request("not json")), get_tree())[0])).is_equal(400)
	var reply := _handler().respond(DebugHandler.parse_request(_request("{\"method\": \"nope\"}")), get_tree())
	assert_str(str(reply[1]["error"])).contains("find_nodes")


func test_nodes_are_found_by_name_pattern_and_class() -> void:
	var root: Node3D = auto_free(Node3D.new())
	root.name = "DebugRoot"
	var a := Node3D.new()
	a.name = "Crate1"
	var b := Node.new()
	b.name = "Crate2"
	root.add_child(a)
	root.add_child(b)
	add_child(root)
	var found := DebugHandler.find_nodes(root, "Crate*", "", 10)
	assert_int(found.size()).is_equal(2)
	var only_3d := DebugHandler.find_nodes(root, "Crate*", "Node3D", 10)
	assert_int(only_3d.size()).is_equal(1)
	assert_str(str(only_3d[0]["path"])).ends_with("DebugRoot/Crate1")
	assert_int(DebugHandler.find_nodes(root, "*", "", 1).size()).is_equal(1)


func test_a_node_is_described_and_a_property_set() -> void:
	var node: Node3D = auto_free(Node3D.new())
	node.name = "Probe"
	add_child(node)
	var path := str(node.get_path())
	var h := _handler()
	var desc: Dictionary = h.call_method("node", {"path": path}, get_tree())["result"]
	assert_str(desc["class"]).is_equal("Node3D")
	assert_bool((desc["properties"] as Dictionary).has("transform")).is_true()
	var set: Dictionary = h.call_method("set", {"path": path, "property": "position", "value": "Vector3(1, 2, 3)"}, get_tree())
	assert_bool(set.has("result")).is_true()
	assert_vector(node.position).is_equal(Vector3(1, 2, 3))
	assert_bool(h.call_method("set", {"path": path, "property": "nonsense", "value": "1"}, get_tree()).has("error")).is_true()
	assert_bool(h.call_method("node", {"path": "/root/NoSuchNode"}, get_tree()).has("error")).is_true()


func test_get_reads_script_variables_as_text_and_plain_json() -> void:
	var node: Node3D = auto_free(Node3D.new())
	node.name = "GetProbe"
	add_child(node)
	node.position = Vector3(1, 2, 3)
	var got: Dictionary = _handler().call_method("get", {"path": str(node.get_path()), "property": "position"}, get_tree())["result"]
	assert_str(str(got["text"])).is_equal("Vector3(1, 2, 3)")
	assert_array(got["value"]).is_equal([1.0, 2.0, 3.0])
	assert_bool(_handler().call_method("get", {"path": str(node.get_path()), "property": "nope"}, get_tree()).has("error")).is_true()


func test_plain_turns_engine_values_into_json() -> void:
	assert_array(DebugHandler.plain(Vector2(1, 2))).is_equal([1.0, 2.0])
	assert_array(DebugHandler.plain(Color(1, 0, 0, 1))).is_equal([1.0, 0.0, 0.0, 1.0])
	var nested: Dictionary = DebugHandler.plain({1: [Vector3.UP, &"name"]})
	assert_array(nested["1"]).is_equal([[0.0, 1.0, 0.0], "name"])
	assert_str(str(DebugHandler.plain(Transform3D.IDENTITY))).starts_with("Transform3D(")


class CallProbe:
	extends Node
	var given: Array = []

	func give(peer: int, item: String, extra: Dictionary = {}) -> bool:
		given.append([peer, item, extra])
		return true

	func touch(who: Node) -> String:
		return str(who.name)

	func secret() -> String:
		return "unreachable"

	func server_poke() -> String:
		return "poked"


func test_only_allow_listed_methods_are_called() -> void:
	var holder: Node = auto_free(Node.new())
	holder.name = "CallModules"
	var probe := CallProbe.new()
	probe.name = "probe"
	holder.add_child(probe)
	add_child(holder)
	var h := _handler()
	h.modules_path = str(holder.get_path())
	h.calls = ["probe:give", "probe:touch", "missing:give", "probe:server_poke"]
	var ok := h.call_method("call", {"target": "probe:give", "args": ["2", "\"glowstick\""]}, get_tree())
	assert_bool(bool(ok["result"])).is_true()
	assert_array(probe.given).is_equal([[2, "glowstick", {}]])
	# A NodePath argument arrives as the node it points at.
	var touched := h.call_method("call", {"target": "probe:touch", "args": ["NodePath(\"%s\")" % probe.get_path()]}, get_tree())
	assert_str(str(touched["result"])).is_equal("probe")
	assert_str(str(h.call_method("call", {"target": "probe:secret"}, get_tree())["error"])).contains("not callable")
	assert_str(str(h.call_method("call", {"target": "missing:give"}, get_tree())["error"])).contains("not loaded")
	assert_str(str(h.call_method("call", {"target": "probe:give", "args": ["1"]}, get_tree())["error"])).contains("argument")
	assert_bool(h.call_method("call", {"target": "probe:touch", "args": ["NodePath(\"/root/NoSuchNode\")"]}, get_tree()).has("error")).is_true()

	# A client (the handler's role here) has server methods too, but must not run them.
	assert_str(str(h.call_method("call", {"target": "probe:server_poke"}, get_tree())["error"])).contains("server only")
	h.role = "server"
	assert_str(str(h.call_method("call", {"target": "probe:server_poke"}, get_tree())["result"])).is_equal("poked")


func test_plain_cuts_long_containers_and_names_freed_objects() -> void:
	var long := range(DebugHandler.MAX_ITEMS + 50)
	assert_int((DebugHandler.plain(long) as Array).size()).is_equal(DebugHandler.MAX_ITEMS)
	var gone := Node.new()
	gone.free()
	assert_str(str(DebugHandler.plain([gone])[0])).is_equal("<freed>")


## Every allowed call names a method its module's entry script really has, so a rename
## breaks this test, not a playtest an hour later. A deleted module's entries are skipped.
func test_every_allowed_call_exists_on_its_module() -> void:
	for target: String in DebugHandler.CALLS:
		var at := target.rfind(":")
		var id := target.substr(0, at)
		if not FileAccess.file_exists("res://modules/%s/module.json" % id):
			continue
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://modules/%s/module.json" % id))
		assert_bool(manifest is Dictionary).override_failure_message("%s: no module.json" % target).is_true()
		# Read as text: loading every module's script here would compile half the game.
		var source := FileAccess.get_file_as_string("res://modules/%s/%s" % [id, str((manifest as Dictionary).get("entry", ""))])
		assert_bool(source.contains("\nfunc %s(" % target.substr(at + 1))).override_failure_message("%s: no such method" % target).is_true()


func test_settings_change_this_process_only_from_the_list() -> void:
	var h := _handler()
	var before: Variant = Settings.value("colour_blind")
	var heard: Array = []
	var on_changed := func(p: Dictionary) -> void: heard.append(p)
	EventBus.subscribe(&"settings.changed", on_changed)
	var got := h.call_method("setting", {"key": "colour_blind", "value": not before}, get_tree())
	EventBus.unsubscribe(&"settings.changed", on_changed)
	assert_bool(bool(got["result"])).is_equal(not before)
	assert_bool(bool(Settings.value("colour_blind"))).is_equal(not before)
	assert_array(heard.map(func(p: Dictionary) -> String: return str(p["key"]))).contains(["colour_blind"])
	# Off the list, or the wrong type: refused and left alone.
	assert_str(str(h.call_method("setting", {"key": "fullscreen", "value": true}, get_tree())["error"])).contains("not a setting")
	assert_str(str(h.call_method("setting", {"key": "colour_blind", "value": "yes"}, get_tree())["error"])).contains("takes a bool")
	assert_bool(bool(Settings.value("colour_blind"))).is_equal(not before)
	Settings.set_value("colour_blind", before)

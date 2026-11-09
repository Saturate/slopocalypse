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

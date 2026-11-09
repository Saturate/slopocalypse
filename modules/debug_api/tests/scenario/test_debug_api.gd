extends GdUnitTestSuite
## A real round trip: the module listens on loopback and answers an HTTP request with the
## token. The flag is off in tests, so the listener is started by hand.


func test_it_answers_over_tcp() -> void:
	var api: Node = auto_free((load("res://modules/debug_api/debug_api_module.gd") as GDScript).new())
	add_child(api)
	# Started by hand: the --debug-api flag is not on the test command line.
	var server := TCPServer.new()
	assert_int(server.listen(0, "127.0.0.1")).is_equal(OK)
	api.set(&"_server", server)
	var handler: DebugHandler = api.get(&"_handler")
	handler.token = "abc"
	var peer := StreamPeerTCP.new()
	assert_int(peer.connect_to_host("127.0.0.1", server.get_local_port())).is_equal(OK)
	var body := "{\"method\": \"state\"}"
	var sent := false
	var reply := PackedByteArray()
	for i in 200:
		await get_tree().process_frame
		peer.poll()
		# Reading a socket the server has already closed is an engine error: check first.
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			if sent:
				break
			continue
		if not sent:
			peer.put_data(("POST /rpc HTTP/1.1\r\nAuthorization: Bearer abc\r\nContent-Length: %d\r\n\r\n%s" % [body.length(), body]).to_utf8_buffer())
			sent = true
		var available := peer.get_available_bytes()
		if available > 0:
			reply = reply + (peer.get_data(available)[1] as PackedByteArray)
	var text := reply.get_string_from_utf8()
	assert_str(text).starts_with("HTTP/1.1 200")
	var json: Dictionary = JSON.parse_string(text.substr(text.find("\r\n\r\n") + 4))
	assert_int(int(json["result"]["pid"])).is_equal(OS.get_process_id())
	assert_bool((json["result"] as Dictionary).has("modules")).is_true()

extends GdUnitTestSuite
## A real round trip over TCP: the page and the JSON answer, other paths and methods do not,
## and an oversized request is never answered.

var _web: Node


func before_test() -> void:
	_web = auto_free((load("res://modules/web/web_module.gd") as GDScript).new())
	add_child(_web)
	# Started by hand: the --web flag is not on the test command line.
	assert_bool(_web.call(&"listen", 0, "127.0.0.1")).is_true()


## Sends `request` and returns the whole reply.
func _ask(request: String) -> String:
	var peer := StreamPeerTCP.new()
	assert_int(peer.connect_to_host("127.0.0.1", int(_web.call(&"port")))).is_equal(OK)
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
			peer.put_data(request.to_utf8_buffer())
			sent = true
		var available := peer.get_available_bytes()
		if available > 0:
			reply = reply + (peer.get_data(available)[1] as PackedByteArray)
	return reply.get_string_from_utf8()


func test_status_json_answers() -> void:
	var text := await _ask("GET /status.json HTTP/1.1\r\nHost: x\r\n\r\n")
	assert_str(text).starts_with("HTTP/1.1 200")
	var json: Variant = JSON.parse_string(text.substr(text.find("\r\n\r\n") + 4))
	assert_bool(json is Dictionary and (json as Dictionary).has("players")).is_true()


func test_the_page_answers() -> void:
	var text := await _ask("GET / HTTP/1.1\r\n\r\n")
	assert_str(text).starts_with("HTTP/1.1 200")
	assert_str(text).contains("text/html")
	assert_str(text).contains("Players online")


func test_other_paths_and_methods_are_refused() -> void:
	assert_str(await _ask("GET /admin HTTP/1.1\r\n\r\n")).starts_with("HTTP/1.1 404")
	assert_str(await _ask("POST / HTTP/1.1\r\nContent-Length: 0\r\n\r\n")).starts_with("HTTP/1.1 405")


func test_an_oversized_request_is_refused() -> void:
	var huge := "GET / HTTP/1.1\r\nX-Pad: %s\r\n\r\n" % "a".repeat(9000)
	# Refused with a 413, or cut off before the client finishes sending; never answered.
	var reply := await _ask(huge)
	assert_bool(reply.is_empty() or reply.begins_with("HTTP/1.1 413")).is_true()

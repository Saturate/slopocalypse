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
	assert_str(await _ask("GET /nowhere HTTP/1.1\r\n\r\n")).starts_with("HTTP/1.1 404")
	assert_str(await _ask("POST / HTTP/1.1\r\nContent-Length: 0\r\n\r\n")).starts_with("HTTP/1.1 405")


func test_an_oversized_request_is_refused() -> void:
	var huge := "GET / HTTP/1.1\r\nX-Pad: %s\r\n\r\n" % "a".repeat(9000)
	# Refused with a 413, or cut off before the client finishes sending; never answered.
	var reply := await _ask(huge)
	assert_bool(reply.is_empty() or reply.begins_with("HTTP/1.1 413")).is_true()


func _basic(password: String) -> String:
	return "Authorization: Basic %s\r\n" % Marshalls.utf8_to_base64("admin:" + password)


func test_without_a_password_the_admin_pages_are_off() -> void:
	_web.call(&"set_password", "")
	assert_str(await _ask("GET /admin HTTP/1.1\r\n\r\n")).starts_with("HTTP/1.1 404")


func test_the_admin_pages_ask_for_the_password_and_the_status_does_not() -> void:
	_web.call(&"set_password", "hunter2")
	var asked := await _ask("GET /admin HTTP/1.1\r\n\r\n")
	assert_str(asked).starts_with("HTTP/1.1 401")
	assert_str(asked).contains("WWW-Authenticate: Basic")
	assert_str(await _ask("GET /admin HTTP/1.1\r\n%s\r\n" % _basic("wrong"))).starts_with("HTTP/1.1 401")
	assert_str(await _ask("GET /admin HTTP/1.1\r\n%s\r\n" % _basic("hunter2"))).starts_with("HTTP/1.1 200")
	assert_str(await _ask("GET / HTTP/1.1\r\n\r\n")).starts_with("HTTP/1.1 200")


func test_guessing_the_password_is_slowed_down() -> void:
	_web.call(&"set_password", "hunter2")
	var limit := int((load("res://modules/web/web_module.gd") as GDScript).get_script_constant_map()["MAX_FAILED_LOGINS"])
	for i in limit:
		assert_str(await _ask("GET /admin HTTP/1.1\r\n%s\r\n" % _basic("guess%d" % i))).starts_with("HTTP/1.1 401")
	# Even the right password waits once the guesses run out.
	assert_str(await _ask("GET /admin HTTP/1.1\r\n%s\r\n" % _basic("hunter2"))).starts_with("HTTP/1.1 429")


func test_an_admin_page_can_be_added_by_another_module() -> void:
	_web.call(&"set_password", "hunter2")
	_web.call(&"add_admin_page", "/admin/hello", "Hello", func(_req: Dictionary) -> Array: return [200, "text/plain", "hi"])
	assert_str(await _ask("GET /admin/hello HTTP/1.1\r\n\r\n")).starts_with("HTTP/1.1 401")
	var reply := await _ask("GET /admin/hello HTTP/1.1\r\n%s\r\n" % _basic("hunter2"))
	assert_str(reply).starts_with("HTTP/1.1 200")
	assert_str(reply).ends_with("hi")
	# Listed on the admin page.
	assert_str(await _ask("GET /admin HTTP/1.1\r\n%s\r\n" % _basic("hunter2"))).contains("/admin/hello")


func test_a_post_body_reaches_its_page() -> void:
	_web.call(&"set_password", "hunter2")
	_web.call(&"add_admin_page", "/admin/echo", "", func(req: Dictionary) -> Array: return [200, "text/plain", str(req["body"])])
	var body := "{\"a\": 1}"
	var reply := await _ask("POST /admin/echo HTTP/1.1\r\n%sContent-Type: application/json\r\nContent-Length: %d\r\n\r\n%s" % [_basic("hunter2"), body.length(), body])
	assert_str(reply).ends_with(body)


func test_a_post_from_another_site_or_not_json_is_refused() -> void:
	_web.call(&"set_password", "hunter2")
	_web.call(&"add_admin_page", "/admin/echo", "", func(req: Dictionary) -> Array: return [200, "text/plain", str(req["body"])])
	var form := "a=1"
	assert_str(await _ask("POST /admin/echo HTTP/1.1\r\n%sContent-Type: text/plain\r\nContent-Length: 3\r\n\r\n%s" % [_basic("hunter2"), form])).starts_with("HTTP/1.1 415")
	assert_str(await _ask("POST /admin/echo HTTP/1.1\r\nHost: slop.example\r\nOrigin: https://evil.example\r\n%sContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}" % _basic("hunter2"))).starts_with("HTTP/1.1 403")
	assert_str(await _ask("POST /admin/echo HTTP/1.1\r\nHost: slop.example\r\nOrigin: https://slop.example\r\n%sContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}" % _basic("hunter2"))).starts_with("HTTP/1.1 200")


func test_one_clients_guesses_do_not_lock_out_another_behind_a_trusted_proxy() -> void:
	_web.call(&"set_password", "hunter2")
	_web.call(&"set_trusted_proxies", "127.0.0.0/8")
	var limit := int((load("res://modules/web/web_module.gd") as GDScript).get_script_constant_map()["MAX_FAILED_LOGINS"])
	for i in limit:
		await _ask("GET /admin HTTP/1.1\r\nX-Real-IP: 203.0.113.9\r\n%s\r\n" % _basic("guess%d" % i))
	assert_str(await _ask("GET /admin HTTP/1.1\r\nX-Real-IP: 203.0.113.9\r\n%s\r\n" % _basic("hunter2"))).starts_with("HTTP/1.1 429")
	assert_str(await _ask("GET /admin HTTP/1.1\r\nX-Real-IP: 198.51.100.7\r\n%s\r\n" % _basic("hunter2"))).starts_with("HTTP/1.1 200")


func test_odd_requests_get_a_plain_refusal() -> void:
	_web.call(&"set_password", "hunter2")
	assert_str(await _ask("GET / HTTP/1.1\r\nContent-Length: lots\r\n\r\n")).starts_with("HTTP/1.1 400")
	assert_str(await _ask("GET /admin HTTP/1.1\r\nAuthorization: Basic !!notbase64!!\r\n\r\n")).starts_with("HTTP/1.1 401")
	var head := await _ask("HEAD / HTTP/1.1\r\n\r\n")
	assert_str(head).starts_with("HTTP/1.1 200")
	assert_str(head.substr(head.find("\r\n\r\n") + 4)).is_empty()


func test_the_status_is_public_on_the_api_too() -> void:
	var text := await _ask("GET /api/v1/status HTTP/1.1\r\n\r\n")
	assert_str(text).starts_with("HTTP/1.1 200")
	var json: Variant = JSON.parse_string(text.substr(text.find("\r\n\r\n") + 4))
	assert_bool(json is Dictionary and (json as Dictionary).has("players")).is_true()


func test_the_admin_app_is_served_behind_the_password() -> void:
	var dir := "user://test_web_static"
	DirAccess.make_dir_recursive_absolute(dir)
	FileAccess.open(dir + "/index.html", FileAccess.WRITE).store_string("<html>app</html>")
	FileAccess.open(dir + "/app.js", FileAccess.WRITE).store_string("console.log(1)")
	_web.call(&"load_static", dir)
	_web.call(&"set_password", "hunter2")
	assert_str(await _ask("GET /admin/app/ HTTP/1.1\r\n\r\n")).starts_with("HTTP/1.1 401")
	var page := await _ask("GET /admin/app/ HTTP/1.1\r\n%s\r\n" % _basic("hunter2"))
	assert_str(page).starts_with("HTTP/1.1 200")
	assert_str(page).contains("text/html")
	assert_str(page).ends_with("<html>app</html>")
	var script := await _ask("GET /admin/app/app.js HTTP/1.1\r\n%s\r\n" % _basic("hunter2"))
	assert_str(script).contains("text/javascript")
	# Only files that were there at start: no way out of the folder.
	assert_str(await _ask("GET /admin/app/../../project.godot HTTP/1.1\r\n%s\r\n" % _basic("hunter2"))).starts_with("HTTP/1.1 404")
	assert_str(await _ask("GET /admin/app/nope.js HTTP/1.1\r\n%s\r\n" % _basic("hunter2"))).starts_with("HTTP/1.1 404")
	# Listed on the admin page.
	assert_str(await _ask("GET /admin HTTP/1.1\r\n%s\r\n" % _basic("hunter2"))).contains("/admin/app/")
	for f in ["index.html", "app.js"]:
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)

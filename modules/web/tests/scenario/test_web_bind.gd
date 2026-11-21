extends GdUnitTestSuite
## A page bound to 127.0.0.1 (a proxy on the same host in front) cannot be reached through
## the machine's other addresses, while one bound to every address can (#448).

const WEB := "res://modules/web/web_module.gd"


## One of this machine's IPv4 addresses other than loopback, or "" on a machine without one.
func _outside_address() -> String:
	for address in IP.get_local_addresses():
		if address.is_valid_ip_address() and not address.contains(":") and not address.begins_with("127."):
			return address
	return ""


func _start(bind: String) -> Node:
	var web: Node = auto_free((load(WEB) as GDScript).new())
	add_child(web)
	assert_bool(web.call(&"listen", 0, bind)).is_true()
	return web


## Whether a connection to `address`:`port` is accepted and answered within a few frames.
func _answers(address: String, port: int) -> bool:
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host(address, port) != OK:
		return false
	var sent := false
	for i in 120:
		await get_tree().process_frame
		peer.poll()
		var status := peer.get_status()
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			return false
		if status != StreamPeerTCP.STATUS_CONNECTED:
			continue
		if not sent:
			peer.put_data("GET /status.json HTTP/1.1\r\n\r\n".to_utf8_buffer())
			sent = true
		if peer.get_available_bytes() > 0:
			var got: Array = peer.get_data(peer.get_available_bytes())
			peer.disconnect_from_host()
			return (got[1] as PackedByteArray).get_string_from_utf8().begins_with("HTTP/1.1 200")
	peer.disconnect_from_host()
	return false


func test_bound_to_loopback_only_loopback_gets_in() -> void:
	var outside := _outside_address()
	var web := _start("127.0.0.1")
	var port := int(web.call(&"port"))
	assert_bool(await _answers("127.0.0.1", port)).is_true()
	if outside.is_empty():
		# Nothing but loopback here (a sandbox without a network): nothing more to prove.
		return
	assert_bool(await _answers(outside, port)).override_failure_message("a page bound to 127.0.0.1 answered on %s" % outside).is_false()


func test_bound_everywhere_other_addresses_get_in() -> void:
	var outside := _outside_address()
	if outside.is_empty():
		return
	var web := _start("*")
	assert_bool(await _answers(outside, int(web.call(&"port")))).override_failure_message("a page on every address did not answer on %s" % outside).is_true()

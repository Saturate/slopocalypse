extends Node
## Live debug API for people and agents, off unless the game runs with `--debug-api` (the solo
## server gets the flag too). Listens on 127.0.0.1 on a free port and answers `POST /rpc`
## (see DebugHandler) for anyone holding the random token. The port and token go in
## user://debug/api-<pid>.json, which tools/mcp/server.ts reads; the file goes when the game
## quits. Never on unless asked for: it can read and change anything in the running game.

const FLAG := "--debug-api"
## Requests that have not arrived in full by then are dropped.
const REQUEST_TIMEOUT_MS := 5000

var _server: TCPServer
var _handler := DebugHandler.new()
var _clients: Array[Dictionary] = []
var _file := ""


func _ready() -> void:
	if not OS.get_cmdline_user_args().has(FLAG):
		return
	_server = TCPServer.new()
	var err := _server.listen(0, "127.0.0.1")
	if err != OK:
		Log.warn(&"debug_api", "cannot listen: %s" % error_string(err))
		_server = null
		return
	var crypto := Crypto.new()
	_handler.token = crypto.generate_random_bytes(16).hex_encode()
	_handler.role = _role()
	_handler.log_path = _log_path()
	DirAccess.make_dir_recursive_absolute("user://debug")
	_file = "user://debug/api-%d.json" % OS.get_process_id()
	var info := {"pid": OS.get_process_id(), "role": _handler.role, "port": _server.get_local_port(), "token": _handler.token, "log": _handler.log_path}
	var f := FileAccess.open(_file, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(info))
		f.close()
	Log.info(&"debug_api", "listening on 127.0.0.1:%d (%s)" % [_server.get_local_port(), ProjectSettings.globalize_path(_file)])


func _exit_tree() -> void:
	if _server != null:
		_server.stop()
	if not _file.is_empty():
		DirAccess.remove_absolute(_file)


## The port it listens on (0 when off).
func port() -> int:
	return _server.get_local_port() if _server != null else 0


func token() -> String:
	return _handler.token


func _process(_delta: float) -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		_clients.append({"peer": _server.take_connection(), "data": PackedByteArray(), "since": Time.get_ticks_msec()})
	for client: Dictionary in _clients.duplicate():
		var peer: StreamPeerTCP = client["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.erase(client)
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var got := peer.get_data(available)
			if int(got[0]) == OK:
				# Packed arrays are values: appending to a cast copy would change nothing.
				client["data"] = (client["data"] as PackedByteArray) + (got[1] as PackedByteArray)
		var request := DebugHandler.parse_request(client["data"])
		if request["complete"]:
			var reply := _handler.respond(request, get_tree())
			_send(peer, int(reply[0]), reply[1])
			_clients.erase(client)
		elif Time.get_ticks_msec() - int(client["since"]) > REQUEST_TIMEOUT_MS:
			peer.disconnect_from_host()
			_clients.erase(client)


func _send(peer: StreamPeerTCP, status: int, body: Dictionary) -> void:
	var payload := JSON.stringify(body).to_utf8_buffer()
	var reason: String = {200: "OK", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 413: "Payload Too Large"}.get(status, "Error")
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, reason, payload.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(payload)
	peer.disconnect_from_host()


func _role() -> String:
	if DisplayServer.get_name() == "headless" and not Net.has_local_player():
		return "server"
	return "client"


## The file this process logs to: the solo server is told with --log-file= (Godot keeps its
## own --log-file to itself), otherwise the project's log file.
func _log_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--log-file="):
			return ProjectSettings.globalize_path(arg.trim_prefix("--log-file="))
	return ProjectSettings.globalize_path(str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log")))

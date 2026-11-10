extends Node
## A dedicated server's web page, for browsers: started with `--web` on a server (the Docker
## image passes it). Listens for HTTP on TCP at the game's port number (the game itself
## talks UDP there, so they never meet) or at `--web-port=N`, and answers `GET /` (a small
## status page) and `GET /status.json` (the same as JSON, for bots and dashboards).
## Read-only and public: nothing secret is shown and nothing in the game can be changed
## from it. Admin actions behind a login come later (#235). Requests are size and time
## limited so a slow or hostile client cannot stall the game.

const FLAG := "--web"
const PORT_FLAG := "--web-port="
## A request whose head has not arrived by then is dropped; bigger heads are refused.
const REQUEST_TIMEOUT_MS := 3000
const MAX_HEAD_BYTES := 8192
const MAX_CLIENTS := 32

var _server: TCPServer
var _clients: Array[Dictionary] = []
var _started := 0


func _ready() -> void:
	_started = Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	if not args.has(FLAG) or Net.mode != Net.Mode.SERVER:
		return
	var port := Net.port
	for arg in args:
		if arg.begins_with(PORT_FLAG):
			port = int(arg.trim_prefix(PORT_FLAG))
	listen(port, "*")


## Starts listening (tests call this directly). False if the port is taken.
func listen(port: int, bind: String = "*") -> bool:
	_server = TCPServer.new()
	var err := _server.listen(port, bind)
	if err != OK:
		Log.warn(&"web", "cannot listen on TCP %d: %s" % [port, error_string(err)])
		_server = null
		return false
	Log.info(&"web", "status page on http://<this server>:%d/" % _server.get_local_port())
	return true


func port() -> int:
	return _server.get_local_port() if _server != null else 0


func _exit_tree() -> void:
	if _server != null:
		_server.stop()


func _process(_delta: float) -> void:
	if _server == null:
		return
	var prof := Prof.start()
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if _clients.size() >= MAX_CLIENTS:
			peer.disconnect_from_host()
			continue
		_clients.append({"peer": peer, "data": PackedByteArray(), "since": Time.get_ticks_msec()})
	for client: Dictionary in _clients.duplicate():
		var peer: StreamPeerTCP = client["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.erase(client)
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var got := peer.get_data(mini(available, MAX_HEAD_BYTES + 1))
			if int(got[0]) == OK:
				# Packed arrays are values: appending to a cast copy would change nothing.
				client["data"] = (client["data"] as PackedByteArray) + (got[1] as PackedByteArray)
		var data: PackedByteArray = client["data"]
		var text := data.get_string_from_utf8()
		if data.size() > MAX_HEAD_BYTES:
			_send(peer, 413, "text/plain", "request too large")
			_clients.erase(client)
		elif text.contains("\r\n\r\n"):
			var reply := respond(text.substr(0, text.find("\r\n")))
			_send(peer, int(reply[0]), str(reply[1]), str(reply[2]))
			_clients.erase(client)
		elif Time.get_ticks_msec() - int(client["since"]) > REQUEST_TIMEOUT_MS:
			peer.disconnect_from_host()
			_clients.erase(client)
	Prof.stop(&"web/module:frame", prof)


## `[status, content type, body]` for a request line such as "GET /status.json HTTP/1.1".
func respond(request_line: String) -> Array:
	var parts := request_line.split(" ")
	var method := parts[0] if parts.size() > 0 else ""
	var path := parts[1].split("?")[0] if parts.size() > 1 else ""
	if method != "GET" and method != "HEAD":
		return [405, "text/plain", "GET only"]
	match path:
		"/", "/index.html":
			return [200, "text/html; charset=utf-8", WebStatus.html(WebStatus.build(get_tree(), _started))]
		"/status.json":
			return [200, "application/json", JSON.stringify(WebStatus.build(get_tree(), _started))]
	return [404, "text/plain", "not found"]


func _send(peer: StreamPeerTCP, status: int, content_type: String, body: String) -> void:
	var payload := body.to_utf8_buffer()
	var reason: String = {200: "OK", 404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large"}.get(status, "Error")
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n" % [status, reason, content_type, payload.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(payload)
	peer.disconnect_from_host()

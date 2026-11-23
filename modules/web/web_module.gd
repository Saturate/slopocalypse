extends Node
## A dedicated server's web page, for browsers: started with `--web` on a server (the Docker
## image passes it). Listens for HTTP on TCP at the game's port number (the game itself
## talks UDP there, so they never meet) or at `--web-port=N`, on every address or the one
## `--web-bind=` names (a proxy in front, #448), and answers `GET /` (a small
## status page) and `GET /status.json` (the same as JSON, for bots and dashboards): read-only
## and public. Under `/admin` are pages other modules add (`add_admin_page`: the map viewer,
## the live map), behind a password from `WEB_PASSWORD` in the environment (HTTP basic auth:
## put HTTPS in front); with no password they are off.
##
## The game must never stall on a visitor: each connection is read and answered a piece per
## frame, its head is scanned once and parsed strictly (anything odd is a plain 400 with no
## log line), and wrong passwords are limited per client. A client is its own address, or
## the address a trusted proxy (`WEB_TRUSTED_PROXY`, e.g. 10.0.0.0/8) says it forwards for.

const FLAG := "--web"
const PORT_FLAG := "--web-port="
## The address to listen on: `*` (every address, the default) or one IP, such as 127.0.0.1
## so only a proxy on the same host (terminating HTTPS) reaches the page.
const BIND_FLAG := "--web-bind="
## The same two for the Docker image, whose command line is fixed: the flags win over these.
const PORT_ENV := "WEB_PORT"
const BIND_ENV := "WEB_BIND"
const PASSWORD_ENV := "WEB_PASSWORD"
## A proxy in front (comma-separated IPv4 ranges such as 10.0.0.0/8) whose X-Real-IP header
## names the visitor; from anywhere else the header is ignored.
const TRUSTED_PROXY_ENV := "WEB_TRUSTED_PROXY"
## A request still arriving after this, or an answer still not taken, is dropped.
const REQUEST_TIMEOUT_MS := 3000
const REPLY_TIMEOUT_MS := 10000
## A page still working on its answer after this (a map render) gets a 503 instead.
const WAIT_TIMEOUT_MS := 60000
const MAX_HEAD_BYTES := 8192
## Bodies (an edited map recipe) no bigger than this.
const MAX_BODY_BYTES := 262144
const MAX_CLIENTS := 32
## Bytes handed to a socket a frame: the rest waits, so a slow reader never holds a frame.
const SEND_CHUNK := 65536
## Wrong passwords one client may try per FAILED_LOGIN_WINDOW_MS; then it waits that out.
const MAX_FAILED_LOGINS := 10
const FAILED_LOGIN_WINDOW_MS := 60000
## The admin web app's built files (web/, `npm run build -w web`), served under APP_PATH.
const STATIC_DIR := "res://modules/web/static"
const APP_PATH := "/admin/app"
const CONTENT_TYPES := {"html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8", "css": "text/css; charset=utf-8",
	"json": "application/json", "svg": "image/svg+xml", "png": "image/png", "ico": "image/x-icon", "woff2": "font/woff2"}
## Shorter passwords work, with a warning in the log.
const MIN_PASSWORD_LENGTH := 12
const REALM := "Slopocalypse admin"
## On public answers only: any site may read the status (dashboards), never an admin page.
const PUBLIC := {"Access-Control-Allow-Origin": "*"}
const REASONS := {200: "OK", 202: "Accepted", 302: "Found", 503: "Service Unavailable", 204: "No Content", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
	404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large", 415: "Unsupported Media Type",
	429: "Too Many Requests", 500: "Internal Server Error"}

var _server: TCPServer
## Per connection: {peer, address, data, since, scanned, head_end, request, out, sent, wait}.
var _clients: Array[Dictionary] = []
var _started := 0
var _password := ""
## Admin pages: path -> {title, handler (Callable(request) -> [status, type, body, headers?])}.
var _admin: Dictionary[String, Dictionary] = {}
## Per client address, when its recent wrong passwords were tried (msec).
var _failed_logins: Dictionary[String, Array] = {}
## [network, mask] per trusted proxy range, as 32-bit numbers.
var _trusted: Array[PackedInt64Array] = []
## The web app's files by name, read once: only these can be asked for.
var _static: Dictionary[String, PackedByteArray] = {}


func _ready() -> void:
	_started = Time.get_ticks_msec()
	add_to_group(&"web_api")
	set_password(OS.get_environment(PASSWORD_ENV))
	set_trusted_proxies(OS.get_environment(TRUSTED_PROXY_ENV))
	load_static(STATIC_DIR)
	var args := OS.get_cmdline_user_args()
	if not args.has(FLAG) or Net.mode != Net.Mode.SERVER:
		return
	var env := {PORT_ENV: OS.get_environment(PORT_ENV), BIND_ENV: OS.get_environment(BIND_ENV)}
	var options := listen_options(args, env, Net.port)
	if not str(options["error"]).is_empty():
		Log.warn(&"web", "%s; the web page stays off" % options["error"])
		return
	listen(int(options["port"]), str(options["bind"]))
	# Modules with admin pages add them now, whichever of them loaded first.
	EventBus.publish(&"web.ready", {"web": self})


## Where to listen: {port, bind, error}, from the `--web-port=` / `--web-bind=` flags in
## `args`, else PORT_ENV / BIND_ENV in `env`, else `game_port` on every address. `error` is
## set when a value makes no sense: then the page stays off, since a mistyped address meant
## for a proxy on this host must not end up open to everyone.
static func listen_options(args: PackedStringArray, env: Dictionary, game_port: int) -> Dictionary:
	var port_text := str(env.get(PORT_ENV, ""))
	var bind := str(env.get(BIND_ENV, ""))
	for arg in args:
		if arg.begins_with(PORT_FLAG):
			port_text = arg.trim_prefix(PORT_FLAG)
		elif arg.begins_with(BIND_FLAG):
			bind = arg.trim_prefix(BIND_FLAG)
	port_text = port_text.strip_edges()
	bind = bind.strip_edges()
	var out := {"port": game_port, "bind": "*" if bind.is_empty() else bind, "error": ""}
	if not port_text.is_empty():
		var port := port_text.to_int() if port_text.is_valid_int() else 0
		if port < 1 or port > 65535:
			out["error"] = "web port %s is not a port number (1-65535)" % port_text
			return out
		out["port"] = port
	if out["bind"] != "*" and not str(out["bind"]).is_valid_ip_address():
		out["error"] = "web address %s is not an IP address or *" % bind
	return out


## Starts listening (tests call this directly). False if the port is taken.
func listen(port: int, bind: String = "*") -> bool:
	_server = TCPServer.new()
	var err := _server.listen(port, bind)
	if err != OK:
		Log.warn(&"web", "cannot listen on TCP %s port %d: %s" % [bind, port, error_string(err)])
		_server = null
		return false
	var host := "<this server>" if bind == "*" else ("[%s]" % bind if bind.contains(":") else bind)
	Log.info(&"web", "status page on http://%s:%d/%s" % [host, _server.get_local_port(), "" if _password.is_empty() else " (admin pages on)"])
	return true


## The admin password; empty turns the admin pages off.
func set_password(value: String) -> void:
	_password = value
	if not value.is_empty() and value.length() < MIN_PASSWORD_LENGTH:
		Log.warn(&"web", "the admin password is shorter than %d characters; a longer one is much harder to guess" % MIN_PASSWORD_LENGTH)


## Trusted proxy ranges, comma separated IPv4 CIDRs ("10.0.0.0/8"); empty trusts none.
func set_trusted_proxies(value: String) -> void:
	_trusted.clear()
	for part in value.split(",", false):
		var cidr := _parse_cidr(part.strip_edges())
		if cidr.is_empty():
			Log.warn(&"web", "%s: not an IPv4 range like 10.0.0.0/8; ignored" % part.strip_edges())
		else:
			_trusted.append(cidr)


## Reads the web app's files from `dir` (flat, as Vite builds it) and serves them under
## APP_PATH; the app's page is listed on /admin. Nothing there (not built): no app page.
func load_static(dir: String) -> void:
	_static.clear()
	var files := DirAccess.get_files_at(dir)
	for f in files:
		var bytes := FileAccess.get_file_as_bytes(dir.path_join(f))
		if not bytes.is_empty():
			_static[f] = bytes
	if _static.has("index.html"):
		add_admin_page(APP_PATH, "Admin app", _serve_static)
	else:
		_admin.erase(APP_PATH)


## A file of the web app by its name; anything else (or a path below it) is not found.
func _serve_static(req: Dictionary) -> Array:
	var rest := str(req["path"]).trim_prefix(APP_PATH).trim_prefix("/")
	var name := "index.html" if rest.is_empty() else rest
	if not _static.has(name):
		return [404, "text/plain", "not found"]
	return [200, CONTENT_TYPES.get(name.get_extension(), "application/octet-stream"), _static[name]]


## Adds an admin page at `path` (and everything under it), listed as `title` on /admin (not
## listed when empty). `handler(request)` gets {method, path, query, headers, body} and
## returns [status, content type, body (text or bytes), extra headers (optional)], or
## {wait: Callable} to answer later (the Callable returns the answer, or null while working).
func add_admin_page(path: String, title: String, handler: Callable) -> void:
	_admin[path] = {"title": title, "handler": handler}


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
		_clients.append({"peer": peer, "address": _plain_ip(peer.get_connected_host()), "data": PackedByteArray(),
			"since": Time.get_ticks_msec(), "scanned": 0, "head_end": -1, "request": {}, "out": PackedByteArray(), "sent": -1, "wait": Callable()})
	for client: Dictionary in _clients.duplicate():
		if not _step(client):
			(client["peer"] as StreamPeerTCP).disconnect_from_host()
			_clients.erase(client)
	Prof.stop(&"web/module:frame", prof)


## One frame of one connection: read, answer once the request is in, send a piece. False
## when it is finished with (answered, gone or too slow).
func _step(client: Dictionary) -> bool:
	var peer: StreamPeerTCP = client["peer"]
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false
	var waited := Time.get_ticks_msec() - int(client["since"])
	if int(client["sent"]) >= 0:
		return _send_some(client) and Time.get_ticks_msec() < int(client["deadline"])
	var wait: Callable = client["wait"]
	if wait.is_valid():
		var ready: Variant = wait.call()
		if ready is Array:
			_queue(client, ready, str((client["request"] as Dictionary)["method"]) == "HEAD")
		elif waited > WAIT_TIMEOUT_MS:
			_queue(client, [503, "text/plain", "still working on it; try again"], false)
		return true
	if waited > REQUEST_TIMEOUT_MS:
		return false
	var available := peer.get_available_bytes()
	if available > 0:
		var got := peer.get_data(mini(available, MAX_HEAD_BYTES + MAX_BODY_BYTES + 1 - (client["data"] as PackedByteArray).size()))
		if int(got[0]) == OK:
			# Packed arrays are values: appending to a cast copy would change nothing.
			client["data"] = (client["data"] as PackedByteArray) + (got[1] as PackedByteArray)
	var data: PackedByteArray = client["data"]
	if int(client["head_end"]) < 0:
		var found := _find_head_end(data, int(client["scanned"]))
		client["scanned"] = data.size()
		if found < 0:
			if data.size() > MAX_HEAD_BYTES:
				_queue(client, [413, "text/plain", "request too large"], false)
			return true
		client["head_end"] = found
		var request := _parse(data, found)
		if request.is_empty():
			_queue(client, [400, "text/plain", "bad request"], false)
			return true
		if int(request["length"]) > MAX_BODY_BYTES:
			_queue(client, [413, "text/plain", "request too large"], false)
			return true
		request["address"] = _visitor(str(client["address"]), request["headers"])
		client["request"] = request
	var req: Dictionary = client["request"]
	var head_end := int(client["head_end"])
	if data.size() - head_end < int(req["length"]):
		return true
	req["body_bytes"] = data.slice(head_end, head_end + int(req["length"]))
	var reply: Variant = handle(req)
	if reply is Dictionary and (reply as Dictionary).get("wait") is Callable:
		# The page answers later (work on another thread): asked again each frame.
		client["wait"] = (reply as Dictionary)["wait"]
	else:
		_queue(client, reply, str(req["method"]) == "HEAD")
	return true


## Turns `reply` ([status, type, body, headers?]) into bytes to send, a piece a frame.
func _queue(client: Dictionary, reply: Array, head_only: bool) -> void:
	var status := int(reply[0])
	var body: Variant = reply[2]
	var payload: PackedByteArray = body if body is PackedByteArray else str(body).to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n" % [
		status, REASONS.get(status, "Error"), _header_safe(str(reply[1])), payload.size()]
	var extra: Dictionary = reply[3] if reply.size() > 3 else {}
	for key: String in extra:
		head += "%s: %s\r\n" % [_header_safe(key), _header_safe(str(extra[key]))]
	client["out"] = (head + "\r\n").to_utf8_buffer() + (PackedByteArray() if head_only else payload)
	client["sent"] = 0
	# A deferred answer gets the usual time to send from when it is ready; every other answer
	# from when the connection came in, so a slow reader holds a slot no longer than before.
	var start := Time.get_ticks_msec() if (client["wait"] as Callable).is_valid() else int(client["since"])
	client["deadline"] = start + REPLY_TIMEOUT_MS


## Sends the next piece; false once all of it is out (or the socket refused it).
func _send_some(client: Dictionary) -> bool:
	var out: PackedByteArray = client["out"]
	var sent := int(client["sent"])
	if sent >= out.size():
		return false
	var result := (client["peer"] as StreamPeerTCP).put_partial_data(out.slice(sent, mini(sent + SEND_CHUNK, out.size())))
	if int(result[0]) != OK:
		return false
	client["sent"] = sent + int(result[1])
	return int(client["sent"]) < out.size()


## No line breaks: a handler's value can never start a header of its own.
static func _header_safe(value: String) -> String:
	return value.replace("\r", "").replace("\n", "")


## Where the head of a request ends (after the blank line), or -1 while it hasn't arrived.
## Scans from `from` on: what came before was scanned in an earlier frame.
static func _find_head_end(data: PackedByteArray, from: int) -> int:
	for i in range(maxi(from, 3), mini(data.size(), MAX_HEAD_BYTES + 4)):
		if data[i] == 10 and data[i - 1] == 13 and data[i - 2] == 10 and data[i - 3] == 13:
			return i + 1
	return -1


## {method, path, query, headers (lower case names), length} from a request's head, or empty
## when it is not a plain HTTP/1.x request (non-ASCII bytes, a bad length...).
static func _parse(data: PackedByteArray, head_end: int) -> Dictionary:
	for i in head_end:
		var b := data[i]
		if b > 126 or (b < 32 and b != 9 and b != 10 and b != 13):
			return {}
	var lines := data.slice(0, head_end).get_string_from_ascii().split("\r\n")
	var parts := lines[0].split(" ")
	if parts.size() != 3 or not parts[2].begins_with("HTTP/1."):
		return {}
	var headers: Dictionary[String, String] = {}
	for line in lines.slice(1):
		var colon := line.find(":")
		if colon > 0:
			headers[line.substr(0, colon).strip_edges().to_lower()] = line.substr(colon + 1).strip_edges()
	var length_text: String = headers.get("content-length", "0")
	if not length_text.is_valid_int() or length_text.length() > 9 or int(length_text) < 0:
		return {}
	var target := parts[1]
	return {"method": parts[0], "path": target.split("?")[0], "query": target.split("?")[1] if target.contains("?") else "",
		"headers": headers, "length": int(length_text), "body": ""}


## `[status, content type, body, headers?]` for a parsed request, or {wait: Callable} from a
## page that answers later: called each frame, it returns the answer once there is one.
func handle(req: Dictionary) -> Variant:
	var method := str(req["method"])
	var path := str(req["path"])
	if path == "/admin" or path.begins_with("/admin/"):
		return _handle_admin(req)
	if method != "GET" and method != "HEAD":
		return [405, "text/plain", "GET only"]
	match path:
		"/", "/index.html":
			return [200, "text/html; charset=utf-8", WebStatus.html(WebStatus.build(get_tree(), _started)), PUBLIC]
		"/status.json", "/api/v1/status":
			return [200, "application/json", JSON.stringify(WebStatus.build(get_tree(), _started)), PUBLIC]
		"/favicon.ico":
			return [204, "text/plain", ""]
	return [404, "text/plain", "not found"]


func _handle_admin(req: Dictionary) -> Variant:
	if _password.is_empty():
		return [404, "text/plain", "not found"]
	var who := str(req.get("address", ""))
	var now := Time.get_ticks_msec()
	var recent: Array = _failed_logins.get(who, []).filter(func(t: int) -> bool: return now - t < FAILED_LOGIN_WINDOW_MS)
	if recent.is_empty():
		_failed_logins.erase(who)
	else:
		_failed_logins[who] = recent
	if recent.size() >= MAX_FAILED_LOGINS:
		return [429, "text/plain", "too many wrong passwords; wait a minute", {"Retry-After": str(roundi(FAILED_LOGIN_WINDOW_MS / 1000.0))}]
	var headers: Dictionary = req["headers"]
	var auth := str(headers.get("authorization", ""))
	if not _password_matches(auth):
		if not auth.is_empty():
			recent.append(now)
			_failed_logins[who] = recent
			Log.info(&"web", "wrong admin password from %s" % who)
		return [401, "text/plain", "password needed", {"WWW-Authenticate": "Basic realm=\"%s\", charset=\"UTF-8\"" % REALM}]
	var method := str(req["method"])
	if method != "GET" and method != "HEAD" and method != "POST":
		return [405, "text/plain", "GET and POST only"]
	if method == "POST":
		# A browser sends the password along with a form posted from any other site; only JSON
		# from this site's own pages gets through (another site can't send JSON without asking).
		if not str(headers.get("content-type", "")).begins_with("application/json"):
			return [415, "text/plain", "JSON only"]
		var origin := str(headers.get("origin", ""))
		var host := str(headers.get("host", ""))
		if not origin.is_empty() and origin != "https://" + host and origin != "http://" + host:
			return [403, "text/plain", "not from this site"]
		var fetch_site := str(headers.get("sec-fetch-site", "same-origin"))
		if fetch_site != "same-origin" and fetch_site != "none":
			return [403, "text/plain", "not from this site"]
	# Decoded only now: a stranger's bytes never reach the text decoder (and its log).
	var bytes: PackedByteArray = req.get("body_bytes", PackedByteArray())
	req["body"] = bytes.get_string_from_utf8() if not bytes.is_empty() else ""
	var path := str(req["path"])
	if path == "/admin" or path == "/admin/":
		# The app is the admin (decision 0011); the plain list stays at /admin/pages, and is the
		# front door of a server without the app.
		if _admin.has(APP_PATH):
			return [302, "text/plain", "", {"Location": APP_PATH + "/"}]
		return [200, "text/html; charset=utf-8", _admin_index()]
	if path == "/admin/pages":
		return [200, "text/html; charset=utf-8", _admin_index()]
	# The longest registered path that the request is at or under.
	var best := ""
	for page: String in _admin:
		if (path == page or path.begins_with(page + "/")) and page.length() > best.length():
			best = page
	if best.is_empty():
		return [404, "text/plain", "not found"]
	return (_admin[best]["handler"] as Callable).call(req)


## Whether an `Authorization: Basic ...` header carries the password (any user name),
## compared in constant time. Malformed headers are just wrong, never logged.
func _password_matches(header: String) -> bool:
	if not header.begins_with("Basic "):
		return false
	var encoded := header.trim_prefix("Basic ").strip_edges()
	if encoded.is_empty() or encoded.length() % 4 != 0 or encoded.length() > 1024:
		return false
	for ch in encoded:
		if not (ch.is_valid_identifier() or ch.is_valid_int() or ch == "+" or ch == "/" or ch == "=") or ch == "_":
			return false
	var raw := Marshalls.base64_to_raw(encoded)
	var colon := raw.find(58)
	if colon < 0:
		return false
	var given := raw.slice(colon + 1)
	var wanted := _password.to_utf8_buffer()
	# Digests are the same length whatever was sent, so the comparison takes the same time.
	var a := _sha256(given)
	var b := _sha256(wanted)
	var diff := 0
	for i in b.size():
		diff |= a[i] ^ b[i]
	return diff == 0


static func _sha256(bytes: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish()


## Who is asking: the connection's address, or the X-Real-IP a trusted proxy sends with it.
func _visitor(address: String, headers: Dictionary) -> String:
	var forwarded := str(headers.get("x-real-ip", ""))
	if forwarded.is_empty() or not _is_trusted(address):
		return address
	return forwarded


func _is_trusted(address: String) -> bool:
	var ip := _ipv4(address)
	if ip < 0:
		return false
	for cidr in _trusted:
		if (ip & cidr[1]) == cidr[0]:
			return true
	return false


## "10.42.0.5" from "::ffff:10.42.0.5" (how an IPv4 visitor shows on a dual-stack socket).
static func _plain_ip(address: String) -> String:
	return address.trim_prefix("::ffff:")


## An IPv4 address as a 32-bit number, or -1.
static func _ipv4(address: String) -> int:
	var parts := _plain_ip(address).split(".")
	if parts.size() != 4:
		return -1
	var out := 0
	for p in parts:
		if not p.is_valid_int() or int(p) < 0 or int(p) > 255:
			return -1
		out = (out << 8) | int(p)
	return out


## [network, mask] for "a.b.c.d/n", or empty.
static func _parse_cidr(text: String) -> PackedInt64Array:
	var parts := text.split("/")
	var ip := _ipv4(parts[0])
	if ip < 0 or parts.size() > 2 or (parts.size() == 2 and not parts[1].is_valid_int()):
		return PackedInt64Array()
	var bits := int(parts[1]) if parts.size() == 2 else 32
	if bits < 0 or bits > 32:
		return PackedInt64Array()
	var mask := (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF if bits > 0 else 0
	return PackedInt64Array([ip & mask, mask])


func _admin_index() -> String:
	var rows: Array[String] = ["<h1>Admin</h1>", "<ul>"]
	for page: String in _admin:
		var title := str(_admin[page]["title"])
		if not title.is_empty():
			# The app's pages load relative to its folder: link it with the trailing slash.
			rows.append("<li><a href=\"%s\">%s</a></li>" % [page + "/" if page == APP_PATH else page, title.xml_escape()])
	rows.append("</ul>")
	if _admin.is_empty():
		rows.append("<p class=dim>No admin pages on this server.</p>")
	return WebStatus.page("Slopocalypse admin", "\n".join(rows))

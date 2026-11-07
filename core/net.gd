class_name NetSession
extends Node
## Networking session, registered as the `Net` autoload. The mode comes from the command
## line (after `--`):
##   --server[=PORT]        dedicated server: headless, no local player
##   --connect=HOST[:PORT]  client joining a server
##   --solo                 solo without the main menu
##   (nothing)              a windowed game shows the main menu (Solo, Host, Join); headless
##                          or tool runs go straight to solo
## Server-only extras: --bind=IP and --quit-when-empty (quit once the last player leaves, or
## if nobody joins at all). Solo passes both.
## Scenes run without Boot (tests, captures) keep Godot's offline peer, which makes this
## instance peer 1 and the server.
##
## Test hook: --net-report-after=FRAMES prints a NET-REPORT line and quits, so tools can
## check a session from the outside.

signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
## Fired when this instance's own connection to its server is up.
signal connected

enum Mode { SOLO, SERVER, CLIENT }

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 8
const SOLO_CONNECT_TRIES := 5
## How long a --quit-when-empty server waits for its first player before giving up.
const FIRST_JOIN_SECONDS := 30.0
## How long joining a server waits before saying it cannot be reached.
const JOIN_TIMEOUT_MS := 8000
## ENet's own defaults, restored after joining.
const ENET_TIMEOUT_LIMIT := 32
const ENET_TIMEOUT_MIN_MS := 5000
const ENET_TIMEOUT_MAX_MS := 30000

var mode: Mode = Mode.SOLO
var port := DEFAULT_PORT
var host := "127.0.0.1"
## Pid of the server this solo session started, or -1.
var solo_server_pid := -1

var _bind_ip := ""
var _quit_when_empty := false
var _had_peers := false
var _connect_tries := 0
var _waited_for_first := 0.0

var _report_after := -1
var _frames := 0

## A person is at the keyboard: failures go back to the menu instead of quitting or erroring.
var interactive := false
## Boot shows the menu instead of starting a session.
var awaiting_menu := false
## Why the last session ended, for the menu to show. Empty after a normal leave.
var menu_message := ""
## The address this instance hosts on when it hosts for friends, or 0.
var hosting_port := 0


## True for a windowed game started without a mode or a tool hook: that is a player who
## wants to choose.
static func wants_menu(args: PackedStringArray, headless: bool) -> bool:
	if headless:
		return false
	for arg in args:
		for prefix in ["--server", "--connect=", "--solo", "--bot=", "--net-report-after="]:
			if arg.begins_with(prefix):
				return false
	return true


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_parse(args)
	var headless := DisplayServer.get_name() == "headless"
	interactive = not headless and not Array(args).any(func(a: String) -> bool: return a.begins_with("--bot=") or a.begins_with("--net-report-after="))
	awaiting_menu = wants_menu(args, headless)
	match mode:
		Mode.SERVER:
			_start_server()
		Mode.CLIENT:
			_start_client()
		_:
			Log.info(&"net", "solo session")
	multiplayer.peer_connected.connect(func(id: int) -> void:
		Log.info(&"net", "peer %d joined" % id)
		_had_peers = true
		peer_joined.emit(id))
	multiplayer.peer_disconnected.connect(_on_peer_left)
	multiplayer.connected_to_server.connect(func() -> void:
		Log.info(&"net", "connected as peer %d" % multiplayer.get_unique_id())
		_restore_timeout()
		connected.emit())
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


## Called by Boot when the game runs without a mode: starts a private server process on
## localhost and joins it like any other client.
func start_solo() -> void:
	if mode != Mode.SOLO or awaiting_menu:
		return
	var p := SoloServer.pick_port()
	if p < 0:
		_fail("No free port for the solo server.")
		return
	_start_local_server(p, SoloServer.BIND_IP)


## Like solo, but the server listens on every interface at `listen_port` so friends can join
## this machine's address (a Tailscale IP, or a forwarded port).
func start_host(listen_port: int) -> void:
	if not SoloServer.is_free(listen_port):
		_fail("Port %d is already in use. Is another server running?" % listen_port)
		return
	hosting_port = listen_port
	_start_local_server(listen_port, "")


## Joins a server by address, from the menu.
func join(to_host: String, to_port: int) -> void:
	mode = Mode.CLIENT
	awaiting_menu = false
	host = to_host
	port = to_port
	_connect_tries = 0
	_start_client()


func _start_local_server(listen_port: int, bind: String) -> void:
	mode = Mode.SOLO
	awaiting_menu = false
	port = listen_port
	host = "127.0.0.1"
	_connect_tries = 0
	var log_file := ProjectSettings.globalize_path("user://logs/solo-server.log")
	solo_server_pid = SoloServer.start(port, OS.get_cmdline_user_args(), log_file, bind)
	if solo_server_pid < 0:
		_fail("Could not start the local server.")
		return
	# Tools read this line to find the child process and its log.
	Log.info(&"net", "solo server pid=%d port=%d log=%s" % [solo_server_pid, port, log_file])
	_start_client()


## Once in, ENet's patient defaults return: loading the world can stall a frame for a
## second or two, and the short join timeout would drop the connection over it.
func _restore_timeout() -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer != null and mode == Mode.CLIENT:
		peer.get_peer(1).set_timeout(ENET_TIMEOUT_LIMIT, ENET_TIMEOUT_MIN_MS, ENET_TIMEOUT_MAX_MS)


func is_session_connected() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Ends this instance's session and reloads Boot into the menu. A local server this game
## started quits on its own once nobody is left on it.
func leave(reason: String = "") -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	mode = Mode.SOLO
	hosting_port = 0
	solo_server_pid = -1
	_connect_tries = 0
	menu_message = reason
	awaiting_menu = true
	get_tree().reload_current_scene.call_deferred()


## A session that cannot start: a player gets the menu and the reason, a tool run an error.
func _fail(reason: String) -> void:
	if interactive:
		Log.warn(&"net", reason)
		leave(reason)
	else:
		Log.error(&"net", reason)


func _on_peer_left(id: int) -> void:
	Log.info(&"net", "peer %d left" % id)
	peer_left.emit(id)
	if _quit_when_empty and _had_peers and multiplayer.get_peers().is_empty():
		Log.info(&"net", "last player left; server quitting")
		get_tree().quit(0)


## A solo server needs a moment to start before it accepts, so solo retries a few times.
func _on_connection_failed() -> void:
	_connect_tries += 1
	if mode == Mode.SOLO and _connect_tries < SOLO_CONNECT_TRIES:
		Log.info(&"net", "solo server not up yet; retrying")
		_start_client()
		return
	_fail("Could not reach %s:%d. Is the host running, and is the address right?" % [host, port])


## A player goes back to the menu; a tool-run client left without a server would spam
## errors every frame, so it says why and closes.
func _on_server_gone() -> void:
	if interactive:
		Log.warn(&"net", "server closed the connection")
		leave("The server closed the connection.")
		return
	Log.warn(&"net", "server closed the connection; quitting")
	multiplayer.multiplayer_peer = null
	get_tree().quit(0)


## Server only: publishes an event here and replays it on every client, so effects
## (explosions, craters) happen everywhere while the decision stays on the server. Nodes in
## the payload travel as paths and are looked up again on the client.
func server_broadcast(topic: StringName, payload: Dictionary) -> void:
	EventBus.publish(topic, payload)
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer or multiplayer.get_peers().is_empty():
		return
	_replay.rpc(topic, _encode(payload))


@rpc("authority", "call_remote", "reliable")
func _replay(topic: StringName, encoded: Dictionary) -> void:
	EventBus.publish(topic, _decode(encoded))


func _encode(payload: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in payload:
		var value: Variant = payload[key]
		if value is Node:
			out[key] = {"__node": String((value as Node).get_path())}
		elif value is Object:
			out[key] = null
		else:
			out[key] = value
	return out


func _decode(encoded: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in encoded:
		var value: Variant = encoded[key]
		if value is Dictionary and (value as Dictionary).has("__node"):
			out[key] = get_node_or_null(NodePath(value["__node"]))
		else:
			out[key] = value
	return out


## True when this instance should have a player of its own (solo or client).
func has_local_player() -> bool:
	return mode != Mode.SERVER


## The peer whose player is controlled from this instance.
func local_peer_id() -> int:
	return multiplayer.get_unique_id()


func _physics_process(delta: float) -> void:
	_watch_empty(delta)
	if _report_after < 0:
		return
	_frames += 1
	if _frames == _report_after:
		print(report())
		# Clients keep running so the server can still count them; they close when it leaves.
		if mode != Mode.CLIENT:
			get_tree().quit(0)


## A solo server must not linger as an orphan. A game that crashes is timed out by ENet and
## counts as leaving; one that never connected is caught here. (Watching the parent pid does
## not work: on Windows Godot only tracks processes it started itself.)
func _watch_empty(delta: float) -> void:
	if not _quit_when_empty or _had_peers:
		return
	_waited_for_first += delta
	if _waited_for_first >= FIRST_JOIN_SECONDS:
		Log.info(&"net", "nobody joined within %d s; server quitting" % int(FIRST_JOIN_SECONDS))
		get_tree().quit(0)


## One line describing the session, for tools and tests. `moved` is the furthest any player
## stands from the world origin (the spawn), `shots` the weapon.fired events seen here,
## `driven` the furthest any vehicle is from where it spawned, `ammo` the local player's
## rounds (group `held_weapons`, method `ammo()`).
func report() -> String:
	var players := get_tree().get_nodes_in_group(&"players")
	# The server owns every player body, so "local" means the player spawned for this peer.
	var me := multiplayer.get_unique_id()
	var local := players.filter(func(p: Node) -> bool: return mode != Mode.SERVER and int(p.get_meta(&"peer_id", 0)) == me)
	var moved := 0.0
	for p: Node in players:
		var at := (p as Node3D).global_position
		moved = maxf(moved, Vector2(at.x, at.z).length())
	# Group and meta names, not a module dependency: whoever spawns vehicles tags them.
	var driven := 0.0
	for v: Node in get_tree().get_nodes_in_group(&"vehicles"):
		var start: Vector3 = v.get_meta(&"spawn_position", (v as Node3D).global_position)
		driven = maxf(driven, (v as Node3D).global_position.distance_to(start))
	# The local player's rounds as this instance shows them (-1 without one): a client only
	# knows what the server tells it.
	var ammo := -1
	for w: Node in get_tree().get_nodes_in_group(&"held_weapons"):
		var holder: Variant = w.get(&"holder")
		if mode != Mode.SERVER and holder is Node and int((holder as Node).get_meta(&"peer_id", 0)) == me and w.has_method(&"ammo"):
			ammo = int(w.call(&"ammo"))
	return "NET-REPORT mode=%s peer=%d peers=%d players=%d local_players=%d moved=%.1f shots=%d driven=%.1f ammo=%d" % [Mode.keys()[mode], me, multiplayer.get_peers().size(), players.size(), local.size(), moved, _shots, driven, ammo]


var _shots := 0


func _enter_tree() -> void:
	# Test hook only: counts shots for the report. A topic name, not a module dependency.
	EventBus.subscribe(&"weapon.fired", func(_p: Dictionary) -> void: _shots += 1)


func _parse(args: PackedStringArray) -> void:
	for arg in args:
		if arg == "--server" or arg.begins_with("--server="):
			mode = Mode.SERVER
			if "=" in arg:
				port = int(arg.split("=")[1])
		elif arg.begins_with("--connect="):
			mode = Mode.CLIENT
			var target := arg.trim_prefix("--connect=")
			var parts := target.split(":")
			host = parts[0]
			if parts.size() > 1:
				port = int(parts[1])
		elif arg.begins_with("--bind="):
			_bind_ip = arg.trim_prefix("--bind=")
		elif arg == "--quit-when-empty":
			_quit_when_empty = true
		elif arg.begins_with("--net-report-after="):
			_report_after = int(arg.trim_prefix("--net-report-after="))


func _start_server() -> void:
	var peer := ENetMultiplayerPeer.new()
	if not _bind_ip.is_empty():
		peer.set_bind_ip(_bind_ip)
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		Log.error(&"net", "could not start server on port %d (%s)" % [port, error_string(err)])
		return
	multiplayer.multiplayer_peer = peer
	Log.info(&"net", "server listening on port %d" % port)


func _start_client() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		_fail("Could not connect to %s:%d (%s)." % [host, port, error_string(err)])
		return
	if mode == Mode.CLIENT:
		# ENet's default gives up after about half a minute; a typo should not cost that.
		# Measured: a failed connect takes about twice the max given here.
		peer.get_peer(1).set_timeout(0, JOIN_TIMEOUT_MS / 4, JOIN_TIMEOUT_MS / 2)
	multiplayer.multiplayer_peer = peer
	Log.info(&"net", "connecting to %s:%d" % [host, port])

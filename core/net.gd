class_name NetSession
extends Node
## Networking session, registered as the `Net` autoload. The mode comes from the command
## line (after `--`):
##   --server[=PORT]        dedicated server: headless, no local player
##   --connect=HOST[:PORT]  client joining a server
##   (nothing)              solo: Boot starts a private server process and joins it
## Server-only extras: --bind=IP and --quit-when-empty (quit once the last player leaves, or
## if nobody joins at all). Solo passes both.
## Scenes run without Boot (tests, captures) keep Godot's offline peer, which makes this
## instance peer 1 and the server.
##
## Test hook: --net-report-after=FRAMES prints a NET-REPORT line and quits, so tools can
## check a session from the outside.

signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

enum Mode { SOLO, SERVER, CLIENT }

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 8
const SOLO_CONNECT_TRIES := 5
## How long a --quit-when-empty server waits for its first player before giving up.
const FIRST_JOIN_SECONDS := 30.0

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


func _ready() -> void:
	_parse(OS.get_cmdline_user_args())
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
	multiplayer.connected_to_server.connect(func() -> void: Log.info(&"net", "connected as peer %d" % multiplayer.get_unique_id()))
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


## Called by Boot when the game runs without a mode: starts a private server process on
## localhost and joins it like any other client.
func start_solo() -> void:
	if mode != Mode.SOLO:
		return
	port = SoloServer.pick_port()
	if port < 0:
		Log.error(&"net", "no free port for the solo server")
		return
	var log_file := ProjectSettings.globalize_path("user://logs/solo-server.log")
	solo_server_pid = SoloServer.start(port, OS.get_cmdline_user_args(), log_file)
	if solo_server_pid < 0:
		Log.error(&"net", "could not start the solo server")
		return
	# Tools read this line to find the child process and its log.
	Log.info(&"net", "solo server pid=%d port=%d log=%s" % [solo_server_pid, port, log_file])
	_start_client()


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
	Log.error(&"net", "could not connect to %s:%d" % [host, port])


## There is no main menu to fall back to yet, and a client left without a server would
## spam errors every frame, so it says why and closes.
func _on_server_gone() -> void:
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
## stands from the world origin (the spawn), `shots` the weapon.fired events seen here.
func report() -> String:
	var players := get_tree().get_nodes_in_group(&"players")
	# The server owns every player body, so "local" means the player spawned for this peer.
	var me := multiplayer.get_unique_id()
	var local := players.filter(func(p: Node) -> bool: return mode != Mode.SERVER and int(p.get_meta(&"peer_id", 0)) == me)
	var moved := 0.0
	for p: Node in players:
		var at := (p as Node3D).global_position
		moved = maxf(moved, Vector2(at.x, at.z).length())
	return "NET-REPORT mode=%s peer=%d peers=%d players=%d local_players=%d moved=%.1f shots=%d" % [Mode.keys()[mode], me, multiplayer.get_peers().size(), players.size(), local.size(), moved, _shots]


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
		Log.error(&"net", "could not start client for %s:%d (%s)" % [host, port, error_string(err)])
		return
	multiplayer.multiplayer_peer = peer
	Log.info(&"net", "connecting to %s:%d" % [host, port])

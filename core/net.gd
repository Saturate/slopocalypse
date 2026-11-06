class_name NetSession
extends Node
## Networking session, registered as the `Net` autoload. The mode comes from the command
## line (after `--`):
##   --server[=PORT]        dedicated server: headless, no local player
##   --connect=HOST[:PORT]  client joining a server
##   (nothing)              solo: this instance is the server and has one local player
## Solo uses the same server code path; without a network peer Godot's offline peer makes
## this instance peer 1.
##
## Test hook: --net-report-after=FRAMES prints a NET-REPORT line and quits, so tools can
## check a session from the outside.

signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

enum Mode { SOLO, SERVER, CLIENT }

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 8

var mode: Mode = Mode.SOLO
var port := DEFAULT_PORT
var host := "127.0.0.1"

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
		peer_joined.emit(id))
	multiplayer.peer_disconnected.connect(func(id: int) -> void:
		Log.info(&"net", "peer %d left" % id)
		peer_left.emit(id))
	multiplayer.connected_to_server.connect(func() -> void: Log.info(&"net", "connected as peer %d" % multiplayer.get_unique_id()))
	multiplayer.connection_failed.connect(func() -> void: Log.error(&"net", "could not connect to %s:%d" % [host, port]))
	multiplayer.server_disconnected.connect(_on_server_gone)


## There is no main menu to fall back to yet, and a client left without a server would
## spam errors every frame, so it says why and closes.
func _on_server_gone() -> void:
	Log.warn(&"net", "server closed the connection; quitting")
	multiplayer.multiplayer_peer = null
	get_tree().quit(0)


## True when this instance should have a player of its own (solo or client).
func has_local_player() -> bool:
	return mode != Mode.SERVER


## The peer whose player is controlled from this instance.
func local_peer_id() -> int:
	return multiplayer.get_unique_id()


func _physics_process(_delta: float) -> void:
	if _report_after < 0:
		return
	_frames += 1
	if _frames == _report_after:
		print(report())
		# Clients keep running so the server can still count them; they close when it leaves.
		if mode != Mode.CLIENT:
			get_tree().quit(0)


## One line describing the session, for tools and tests.
func report() -> String:
	var players := get_tree().get_nodes_in_group(&"players")
	# The server owns every player body, so "local" means the player spawned for this peer.
	var me := multiplayer.get_unique_id()
	var local := players.filter(func(p: Node) -> bool: return mode != Mode.SERVER and int(p.get_meta(&"peer_id", 0)) == me)
	return "NET-REPORT mode=%s peer=%d peers=%d players=%d local_players=%d" % [Mode.keys()[mode], multiplayer.get_unique_id(), multiplayer.get_peers().size(), players.size(), local.size()]


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
		elif arg.begins_with("--net-report-after="):
			_report_after = int(arg.trim_prefix("--net-report-after="))


func _start_server() -> void:
	var peer := ENetMultiplayerPeer.new()
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

class_name SoloServer
extends RefCounted
## Solo play runs the same dedicated server as multiplayer, as a headless child process on
## localhost, so there is one code path and every solo session exercises the netcode.

## Solo servers use their own range so they never collide with a dedicated server on 7777.
const FIRST_PORT := 7800
const PORT_TRIES := 50
const BIND_IP := "127.0.0.1"
## User arguments that shape the world and so must match on the server.
const SHARED_PREFIXES: Array[String] = ["--flags=", "--all-optional-off"]


## Starts the server process. Returns its pid, or -1 when it could not be started.
static func start(port: int, user_args: PackedStringArray, log_file: String) -> int:
	# An exported game carries its project; the editor binary needs to be told where it is.
	var project := "" if OS.has_feature("template") else ProjectSettings.globalize_path("res://")
	var args := server_args(port, user_args, project, log_file)
	return OS.create_process(OS.get_executable_path(), args)


static func server_args(port: int, user_args: PackedStringArray, project: String, log_file: String) -> PackedStringArray:
	var args := PackedStringArray(["--headless"])
	if not project.is_empty():
		args.append_array(["--path", project])
	args.append_array(["--log-file", log_file, "--"])
	# Bound to loopback: a solo world is not open to the network.
	args.append_array(["--server=%d" % port, "--bind=%s" % BIND_IP, "--quit-when-empty"])
	for arg in user_args:
		for prefix in SHARED_PREFIXES:
			if arg.begins_with(prefix):
				args.append(arg)
	return args


## The first port in the solo range nothing is bound to, or -1.
static func pick_port() -> int:
	for port in range(FIRST_PORT, FIRST_PORT + PORT_TRIES):
		var probe := PacketPeerUDP.new()
		var free := probe.bind(port, BIND_IP) == OK
		probe.close()
		if free:
			return port
	return -1

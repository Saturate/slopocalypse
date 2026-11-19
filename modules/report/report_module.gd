extends Node
## Report a bug (#384). In a session, `key` (F8) or "Report a bug" in the Esc menu takes a
## screenshot, asks what happened and writes one zip a tester can send: report.json (machine,
## build, settings, where they were, the newest perf sample), the screenshot, this run's logs
## and perf logs (the solo server's too). It goes to the Desktop and the folder opens.
##
## Other code (the benchmark) writes the same file through `save_report` on `report_api`.

const CONFIG := "res://modules/report/data/report.json"
const REQUIRED := {"key": TYPE_STRING, "max_log_kb": TYPE_FLOAT, "folder_without_desktop": TYPE_STRING}
const SOLO_LOG := "user://logs/solo-server.log"
const PERF_DIR := "user://perf"

var config: Dictionary = {}
## Where the last report went (empty until one is saved).
var last_path := ""
## Overrides the Desktop (tests).
var folder := ""

var _screen: ReportScreen
var _key := KEY_F8


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not (data is Dictionary and Data.require(CONFIG, data, REQUIRED)):
		return
	config = data
	add_to_group(&"report_api")
	if DisplayServer.get_name() == "headless":
		return
	_key = OS.find_keycode_from_string(str(config["key"]))
	if _key == KEY_NONE:
		Log.warn(&"report", "%s: unknown key %s, using F8" % [CONFIG, config["key"]])
		_key = KEY_F8
	_screen = ReportScreen.new()
	_screen.name = "ReportScreen"
	_screen.save_requested.connect(func(description: String, shot: PackedByteArray) -> void:
		_screen.show_saved(save_report("bug", description, shot)))
	add_child(_screen)
	_add_menu_entry.call_deferred()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != _key or _screen == null or _screen.is_open():
		return
	get_viewport().set_input_as_handled()
	open()


## Opens the form, with a screenshot of the game as it is now (before the form covers it).
func open() -> void:
	_screen.open(_screenshot())


## From the Esc menu: the menu is hidden for a frame so the screenshot shows the game, not
## the menu (which can show a host's address).
func open_from_menu() -> void:
	var overlay := get_tree().get_first_node_in_group(&"session_overlay") as CanvasLayer
	if overlay != null:
		overlay.visible = false
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var shot := _screenshot()
		overlay.visible = true
		_screen.open(shot)
	else:
		open()


## Writes a report of `kind` ("bug", "benchmark") with `description` and a screenshot (PNG
## bytes, may be empty), plus `extra` fields for report.json. Returns where it went, or "".
func save_report(kind: String, description: String, shot: PackedByteArray, extra: Dictionary = {}) -> String:
	var report := gather(kind, description)
	report.merge(extra, true)
	var files := attachments()
	if not shot.is_empty():
		files["screenshot.png"] = shot
	var into := _folder()
	DirAccess.make_dir_recursive_absolute(into)
	var path := into.path_join(ReportWriter.file_name(Time.get_datetime_dict_from_system()))
	var err := ReportWriter.write(path, report, files)
	if err != OK:
		Log.warn(&"report", "could not write %s: %s" % [path, error_string(err)])
		return ""
	last_path = path
	Log.info(&"report", "saved %s" % path)
	return path


## report.json: what was asked for, the machine, the game and where the player is.
func gather(kind: String, description: String) -> Dictionary:
	var settings := {}
	for key: String in Settings.DEFAULTS:
		settings[key] = Settings.value(key)
	var perf := get_tree().get_first_node_in_group(&"perf_api")
	return {
		"kind": kind,
		"description": description,
		"time": Time.get_datetime_string_from_system(true),
		"system": ReportWriter.system_info(),
		"settings": settings,
		"game": _game(),
		"perf": perf.call(&"latest") if perf != null else {},
	}


## Files that go with every report: this run's logs and perf logs, newest part of each.
func attachments() -> Dictionary:
	var cap := int(float(config.get("max_log_kb", 2048.0)) * 1024.0)
	var files := {}
	var own_log := _own_log()
	if not own_log.is_empty():
		files["logs/game.log"] = _shareable(own_log, cap)
	if Net.solo_server_pid >= 0:
		files["logs/solo-server.log"] = _shareable(SOLO_LOG, cap)
	for path in _session_perf_logs():
		files["perf/" + path.get_file()] = _shareable(path, cap)
	return files


## The newest `cap` bytes of a log, with home folders and addresses written over.
func _shareable(path: String, cap: int) -> PackedByteArray:
	var text := ReportWriter.tail_of(path, cap).get_string_from_utf8()
	return ReportWriter.scrub(text, _private_folders()).to_utf8_buffer()


## Folders whose full path names the OS user: the user data folder, home, Desktop.
func _private_folders() -> Array[String]:
	var out: Array[String] = [ProjectSettings.globalize_path("user://").trim_suffix("/"), OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP), OS.get_environment("HOME"), OS.get_environment("USERPROFILE")]
	# Longest first, so the user data folder is not half replaced by home.
	out.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	return out


func _game() -> Dictionary:
	var modules: Array[String] = []
	var root := get_parent()
	if root != null:
		for child in root.get_children():
			modules.append(str(child.name))
	var game := {
		"mode": ["solo", "server", "client"][int(Net.mode)],
		"hosting": Net.hosting_port > 0,
		"connected": Net.is_session_connected(),
		"uptime_seconds": Time.get_ticks_msec() / 1000,
		"modules": modules,
		"args": ReportWriter.public_args(OS.get_cmdline_user_args()),
		"flags": _flags(),
	}
	var player := _local_player()
	if player != null:
		game["position"] = [snappedf(player.global_position.x, 0.1), snappedf(player.global_position.y, 0.1), snappedf(player.global_position.z, 0.1)]
		game["dead"] = bool(player.get_meta(&"dead", false))
	return game


## Every feature flag and whether it is on in this run.
func _flags() -> Dictionary:
	var out := {}
	var data: Variant = Data.load_json("res://data/features.json")
	if data is Dictionary and (data as Dictionary).get("flags") is Dictionary:
		for flag: String in (data as Dictionary)["flags"]:
			out[flag] = Features.is_enabled(StringName(flag))
	return out


func _local_player() -> Node3D:
	for node in get_tree().get_nodes_in_group(&"players"):
		if int(node.get_meta(&"peer_id", 0)) == Net.local_peer_id():
			return node as Node3D
	return null


func _screenshot() -> PackedByteArray:
	var image := get_viewport().get_texture().get_image()
	return image.save_png_to_buffer() if image != null else PackedByteArray()


## The Desktop, where a tester finds it; the user folder when there is none.
func _folder() -> String:
	if not folder.is_empty():
		return folder
	var desktop := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if not desktop.is_empty() and DirAccess.dir_exists_absolute(desktop):
		return desktop
	return ProjectSettings.globalize_path(str(config["folder_without_desktop"]))


## The file this process logs to, as the debug API finds it.
func _own_log() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--log-file="):
			return arg.trim_prefix("--log-file=")
	return str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))


## This session's perf logs: ours, and in solo the server's (written since we began).
func _session_perf_logs() -> Array[String]:
	var out: Array[String] = []
	var perf := get_tree().get_first_node_in_group(&"perf_api")
	var mine := str(perf.call(&"log_path")) if perf != null else ""
	if not mine.is_empty():
		out.append(mine)
	# The solo server's own log: perf names its files after the process id.
	if Net.solo_server_pid >= 0 and DirAccess.dir_exists_absolute(PERF_DIR):
		var suffix := "-%d.ndjson" % Net.solo_server_pid
		for name in DirAccess.get_files_at(PERF_DIR):
			if name.begins_with("server-") and name.ends_with(suffix):
				out.append(PERF_DIR.path_join(name))
	return out


func _add_menu_entry() -> void:
	var overlay := get_tree().get_first_node_in_group(&"session_overlay")
	if overlay != null and overlay.has_method(&"add_menu_entry"):
		overlay.call(&"add_menu_entry", &"ReportBug", "Report a bug", open_from_menu)

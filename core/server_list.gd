class_name ServerList
extends RefCounted
## Servers the menu offers to join: the ones this player used, most recent first, then any
## a shared build ships with (a `servers.json` beside the game, written by
## `tools/export.ts --connect`), so a friend's copy already knows where to go.

const SAVE_PATH := "user://servers.json"
const SHIPPED_FILE := "servers.json"
const MAX_RECENT := 8

var _recent: Array[String] = []
var _shipped: Array[String] = []


## `{ok, host, port}` from "host" or "host:port"; the port defaults to NetSession's.
static func parse_address(text: String) -> Dictionary:
	var bad := {"ok": false, "host": "", "port": 0}
	var t := text.strip_edges()
	if t.is_empty() or " " in t:
		return bad
	var host := t
	var port := NetSession.DEFAULT_PORT
	var colon := t.rfind(":")
	if colon >= 0:
		host = t.substr(0, colon)
		var port_text := t.substr(colon + 1)
		if not port_text.is_valid_int():
			return bad
		port = port_text.to_int()
	if host.is_empty() or port < 1 or port > 65535:
		return bad
	return {"ok": true, "host": host, "port": port}


## The shipped list sits next to the executable; when running from the editor there is
## none, which is fine.
static func shipped_path() -> String:
	return OS.get_executable_path().get_base_dir().path_join(SHIPPED_FILE)


static func load_from(saved_path: String = SAVE_PATH, shipped: String = shipped_path()) -> ServerList:
	var list := ServerList.new()
	list._recent = _strings(_read(saved_path).get("recent", []))
	list._shipped = _strings(_read(shipped).get("servers", []))
	return list


func remember(address: String) -> void:
	_recent.erase(address)
	_recent.push_front(address)
	if _recent.size() > MAX_RECENT:
		_recent.resize(MAX_RECENT)


## Recent servers first, then shipped ones not already listed.
func addresses() -> Array[String]:
	var out := _recent.duplicate()
	for a in _shipped:
		if not out.has(a):
			out.append(a)
	return out


func save(path: String = SAVE_PATH) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		Log.warn(&"net", "could not save the server list to %s" % path)
		return
	f.store_string(JSON.stringify({"recent": _recent}, "  "))


## A missing or unreadable file is an empty list: losing recent servers is not worth an
## error dialog.
static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	return json.data


static func _strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for v: Variant in value:
			if v is String and not (v as String).is_empty():
				out.append(v)
	return out

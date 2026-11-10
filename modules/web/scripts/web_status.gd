class_name WebStatus
extends RefCounted
## What a dedicated server tells a browser: who is on, what mission is running, what the
## board offers. `build` gathers it from the running game through other modules' API
## groups (each part is left out when its module is not loaded); `html` turns it into a
## small page. Never anything secret: no player keys, no addresses of players.

const RELEASES := "https://github.com/Saturate/slopocalypse/releases"


static func build(tree: SceneTree, started_msec: int) -> Dictionary:
	var out := {
		"name": "Slopocalypse",
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"uptime_seconds": int((Time.get_ticks_msec() - started_msec) / 1000),
	}
	var players: Array[String] = []
	for node: Node in tree.get_nodes_in_group(&"players"):
		var identity := Net.identity_of(int(node.get_meta(&"peer_id", 0)))
		players.append(str(identity.get("name", node.name)))
	players.sort()
	out["players"] = players
	out["soldiers_alive"] = tree.get_nodes_in_group(&"enemies").filter(func(n: Node) -> bool: return not n.get_meta(&"dead", false)).size()
	var missions := tree.get_first_node_in_group(&"missions_api")
	if missions != null:
		var current: Dictionary = missions.get(&"current")
		out["mission"] = _mission(current) if not current.is_empty() else null
		out["mission_state"] = str(missions.get(&"state"))
		out["board"] = (missions.get(&"offers") as Array).map(func(o: Dictionary) -> Dictionary: return _mission(o))
	return out


static func _mission(m: Dictionary) -> Dictionary:
	return {
		"codename": str(m.get("codename", "")),
		"kind": str(m.get("type_name", "")),
		"place": str(m.get("place", "")),
		"distance_m": int(m.get("distance", 0)),
		"pays": int(m.get("payout", 0)),
	}


## The page: plain, dark, refreshes itself every few seconds.
static func html(status: Dictionary, refresh_seconds: int = 10) -> String:
	var e := func(v: Variant) -> String: return str(v).xml_escape()
	var rows: Array[String] = []
	rows.append("<h1>%s</h1>" % e.call(status.get("name", "Slopocalypse")))
	rows.append("<p class=dim>Version %s &middot; up %s</p>" % [e.call(status.get("version", "")), _duration(int(status.get("uptime_seconds", 0)))])
	var players: Array = status.get("players", [])
	rows.append("<h2>Players online: %d</h2>" % players.size())
	if not players.is_empty():
		rows.append("<ul>%s</ul>" % "".join(players.map(func(p: Variant) -> String: return "<li>%s</li>" % e.call(p))))
	rows.append("<p>Soldiers alive: %d</p>" % int(status.get("soldiers_alive", 0)))
	if status.has("mission_state"):
		var m: Variant = status.get("mission")
		if m is Dictionary:
			var verb := "Out on" if str(status["mission_state"]) == "in_mission" else "Chosen:"
			rows.append("<h2>%s %s</h2><p>%s &middot; %s &middot; %d m &middot; pays %d tokens</p>" % [verb, e.call(m["codename"]), e.call(m["kind"]), e.call(m["place"]), int(m["distance_m"]), int(m["pays"])])
		else:
			rows.append("<h2>At home base</h2>")
		var board: Array = status.get("board", [])
		if not board.is_empty():
			rows.append("<h3>On the board</h3><ul>%s</ul>" % "".join(board.map(func(o: Dictionary) -> String: return "<li><b>%s</b> &middot; %s &middot; %s &middot; %d tokens</li>" % [e.call(o["codename"]), e.call(o["kind"]), e.call(o["place"]), int(o["pays"])])))
	rows.append("<p class=dim>Join from the game's main menu with this server's address. Get the game: <a href=\"%s\">%s</a></p>" % [RELEASES, RELEASES])
	return "<!doctype html><html><head><meta charset=utf-8><meta name=viewport content=\"width=device-width,initial-scale=1\"><meta http-equiv=refresh content=%d><title>Slopocalypse server</title><style>body{background:#151714;color:#e2e1da;font:16px/1.5 system-ui,sans-serif;max-width:720px;margin:2rem auto;padding:0 16px}h1,h2,h3{color:#d19e4c;margin:.8em 0 .3em}a{color:#d19e4c}.dim{color:#9a9b95}ul{padding-left:1.2em}</style></head><body>%s</body></html>" % [refresh_seconds, "\n".join(rows)]


static func _duration(seconds: int) -> String:
	var h := seconds / 3600
	var m := (seconds % 3600) / 60
	return "%dh %dm" % [h, m] if h > 0 else "%dm" % m

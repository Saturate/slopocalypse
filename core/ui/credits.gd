class_name Credits
extends RefCounted
## What the credits screen lists: the people from data/credits.json, and every third-party
## piece from assets/LICENSES.md (read at runtime, so the credits can't drift from it).

const PEOPLE := "res://data/credits.json"
const LICENSES := "res://assets/LICENSES.md"


## [{what, source, licence}] from the licence table, in its order. Paths are left out:
## players care what it is and where it came from.
static func third_party(path := LICENSES) -> Array[Dictionary]:
	if not FileAccess.file_exists(path):
		return []
	return parse_licences(FileAccess.get_file_as_string(path))


static func parse_licences(text: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for raw: String in text.split("\n"):
		var line := raw.strip_edges()
		if not line.begins_with("|") or line.begins_with("| Path") or line.begins_with("| ---"):
			continue
		var cells := line.trim_prefix("|").trim_suffix("|").split("|")
		if cells.size() < 4:
			continue
		var what := _plain(cells[1])
		# Tools only developers run never reach a player's machine.
		if what.contains("dev only") or what.contains("dev tool"):
			continue
		rows.append({"what": what, "source": _plain(cells[2]), "licence": _plain(cells[3])})
	return rows


## {people: [{name, role}], note}
static func people(path := PEOPLE) -> Dictionary:
	var data: Variant = Data.load_json(path)
	return data if data is Dictionary else {}


## Markdown code ticks and the build notes ("fetched by", "licence text in") read badly on
## screen.
static func _plain(cell: String) -> String:
	var s := cell.strip_edges().replace("`", "")
	for cut: String in [" (licence text in", ", fetched by", " (SHA256 pinned)", " (compiled into"]:
		var at := s.find(cut)
		if at >= 0:
			s = s.substr(0, at)
	return s.strip_edges()

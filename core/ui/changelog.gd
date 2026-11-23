class_name Changelog
extends RefCounted
## Reads CHANGELOG.md, as changesetter writes it, into releases for the changelog screen:
## `## <version> - <date>` starts a release; each `#### <text>` line or plain paragraph is one
## change; a `### Internal` section is for developers and left out.

const PATH := "res://CHANGELOG.md"


## Newest first: [{version, date, changes: Array[String]}]. Empty if the file is missing.
static func load_releases(path := PATH) -> Array[Dictionary]:
	if not FileAccess.file_exists(path):
		return []
	return parse(FileAccess.get_file_as_string(path))


static func parse(text: String) -> Array[Dictionary]:
	var releases: Array[Dictionary] = []
	var current: Dictionary = {}
	var internal := false
	for raw: String in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("## "):
			var head := line.substr(3).split(" - ", false, 1)
			current = {"version": head[0].strip_edges(), "date": head[1].strip_edges() if head.size() > 1 else "", "changes": [] as Array[String]}
			releases.append(current)
			internal = false
		elif line.begins_with("### "):
			internal = line.substr(4).strip_edges().to_lower() == "internal"
		elif current.is_empty() or internal or line.is_empty() or line.begins_with("# "):
			continue
		else:
			var change := line.trim_prefix("#### ").strip_edges()
			(current["changes"] as Array[String]).append(change)
	return releases

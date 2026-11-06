class_name LogCapture
## Test helper: flattens captured log entries into plain text. str() on the entries would
## escape quotes, which breaks assertions on messages like "flag 'car' ...".


static func text(entries: Array[Dictionary]) -> String:
	var lines: PackedStringArray = []
	for e in entries:
		lines.append("%s: %s" % [e["category"], e["message"]])
	return "\n".join(lines)

class_name ChangelogScreen
extends ScreenFrame
## Every release, newest first, with what changed for players.

## Narrow enough that a change reads as one or two comfortable lines.
const WIDTH := 640.0


func _init(releases: Array[Dictionary] = Changelog.load_releases()) -> void:
	super("CHANGELOG", WIDTH)
	name = "Changelog"
	if releases.is_empty():
		content.add_child(_line("No changelog in this build.", &"HintLabel"))
	for release: Dictionary in releases:
		var head := HBoxContainer.new()
		head.add_theme_constant_override(&"separation", 12)
		var version := Label.new()
		version.theme_type_variation = &"HeadingLabel"
		version.text = "v%s" % release["version"]
		head.add_child(version)
		var date := Label.new()
		date.theme_type_variation = &"HintLabel"
		date.text = str(release["date"])
		date.size_flags_vertical = Control.SIZE_SHRINK_END
		head.add_child(date)
		content.add_child(head)
		for change: String in release["changes"]:
			content.add_child(_line("·  " + change))
		var gap := Control.new()
		gap.custom_minimum_size.y = 10
		content.add_child(gap)
	add_hint(&"ui_cancel", "Back")


func _line(text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 40.0
	return l

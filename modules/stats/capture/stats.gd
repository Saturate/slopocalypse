extends Node
## Capture setup: the stats screen with a few kills, deaths and a long shot.

const STATS := "res://modules/stats/stats_module.gd"


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UiPalette.BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var stats: Node = (load(STATS) as GDScript).new()
	add_child(stats)
	stats.set(&"mine", {"kills.soldier": 23.0, "kills.soldier.militia": 14.0, "kills.soldier.regulars": 6.0, "kills.soldier.scavengers": 3.0, "kills.player": 1.0, "kills.drone": 5.0, "headshots": 9.0, "longest_kill": 212.4, "deaths": 7.0})
	(stats.get_node(^"StatsScreen") as StatsScreen).open()

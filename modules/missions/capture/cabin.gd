extends "res://modules/missions/capture/site_mission.gd"
## Capture setup: the cabin in the woods: the lone cabin with the mission's shed, a warning
## sign and the minefield round them, from the drop-off up the cabin's track, then from above.


func _init() -> void:
	kind = "cabin"
	place = "Cabin in the woods"
	above = 45.0
	back = 20.0

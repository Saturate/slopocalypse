extends "res://modules/sites/capture/site_view.gd"
## Capture setup: the first farm site of the default map and what stands on it, from the
## track leading to it.


func _init() -> void:
	kind = "farm"
	from_distance = 40.0
	to_distance = 26.0
	look_up = 4.0

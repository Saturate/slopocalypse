extends "res://modules/sites/capture/site_view.gd"
## Capture setup: the first lookout site of the default map and what stands on it, from the
## track leading to it.


func _init() -> void:
	kind = "lookout"
	from_distance = 20.0
	to_distance = 12.0
	look_up = 4.5

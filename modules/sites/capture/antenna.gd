extends "res://modules/sites/capture/site_view.gd"
## Capture setup: the first antenna site of the default map and what stands on it, from the
## track leading to it.


func _init() -> void:
	kind = "antenna"
	from_distance = 30.0
	to_distance = 20.0
	look_up = 10.0

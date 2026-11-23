extends "res://modules/sites/capture/site_view.gd"
## Capture setup: the first cabin site of the default map and what stands on it, from the
## track leading to it.


func _init() -> void:
	kind = "cabin"
	from_distance = 18.0
	to_distance = 11.0
	look_up = 1.8

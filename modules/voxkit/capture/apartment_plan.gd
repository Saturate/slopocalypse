extends "res://modules/voxkit/capture/apartment_cutaway.gd"
## Capture setup: one floor of a furnished apartment block seen from above with everything
## over head height sliced off.


func _init() -> void:
	slice = 1.7
	camera_from = Vector3(0.0, 24.0, 9.0)
	camera_to = Vector3(0.0, 2.0, 0.5)

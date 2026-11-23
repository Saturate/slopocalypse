extends "res://modules/voxkit/capture/apartment_cutaway.gd"
## Capture setup: one floor of a block of wide flats (three windows each) seen from above with
## everything over head height sliced off.


func _init() -> void:
	slice = 1.7
	values = {"floors": 3.0, "stairwells": 1.0, "windows": 3.0, "flat_width": 7.5, "seed": 2.0}
	camera_from = Vector3(0.0, 27.0, 10.0)
	camera_to = Vector3(0.0, 2.0, 0.5)

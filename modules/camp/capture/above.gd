extends "res://modules/camp/capture/camp_view.gd"
## Capture setup: the whole camp from above and behind its back fence, the highway leaving
## through the gate at the far side.


func _init() -> void:
	from = Vector3(-10.0, 34.0, -36.0)
	to = Vector3(-4.0, 32.0, -33.0)
	look = Vector3(0.0, 0.0, 1.0)
	fov = 60.0

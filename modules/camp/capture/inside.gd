extends "res://modules/camp/capture/camp_view.gd"
## Capture setup: inside the camp by the respawn, turning from the hut's door across the
## mission board to the trader's stall.


func _init() -> void:
	from = Vector3(-3.0, 1.7, -1.5)
	to = Vector3(3.0, 1.7, -1.5)
	look = Vector3(0.0, 1.2, -10.0)

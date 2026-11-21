extends "res://modules/camp/capture/camp_view.gd"
## Capture setup: from the respawn toward the gate, over the parking apron where the
## transport and the players' car stand nose to the gate.


func _init() -> void:
	from = Vector3(-1.0, 1.8, -3.0)
	to = Vector3(1.0, 2.2, -1.0)
	look = Vector3(0.0, 0.6, 7.0)

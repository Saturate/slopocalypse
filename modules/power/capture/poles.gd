extends "res://modules/power/capture/line_view.gd"
## Capture setup: a pole line beside the road on the default map, seen from across the road
## near the town or city it starts from, looking along it out toward the farm it feeds.


func _init() -> void:
	kind = "low_voltage"
	tower = 2
	side = -14.0
	back_from = 24.0
	back_to = 10.0
	ahead = 3
	look_up = 4.0

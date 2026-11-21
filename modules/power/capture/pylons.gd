extends "res://modules/power/capture/line_view.gd"
## Capture setup: the default map's first high-voltage line striding away across the fields,
## seen from behind and beside its second pylon, the line running on past it.


func _init() -> void:
	kind = "high_voltage"
	tower = 1
	side = 20.0
	back_from = 55.0
	back_to = 38.0
	ahead = 0
	look_up = 15.0

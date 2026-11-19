extends Node
## Gore: blood where bullets hit people, marks behind them and pools under the dead (#385).
## Client-only and purely for show: a dedicated server, which draws nothing, loads nothing.


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var effects := BloodEffects.new()
	effects.name = "Blood"
	add_child(effects)

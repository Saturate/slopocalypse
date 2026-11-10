class_name RideFade
extends CanvasLayer
## Client only: the screen goes black and comes back when the car takes you somewhere, so
## the jump does not show.

var _black: ColorRect


func _ready() -> void:
	layer = 60
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.modulate.a = 0.0
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_black)
	EventBus.subscribe(&"missions.ride", _on_ride)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"missions.ride", _on_ride)


func _on_ride(p: Dictionary) -> void:
	var seconds := float(p.get("seconds", 0.8))
	_black.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(seconds * 0.4)
	tween.tween_property(_black, "modulate:a", 0.0, seconds * 0.6)

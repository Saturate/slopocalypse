class_name MissionPrompt
extends CanvasLayer
## Client only, local player: what F does at the board and the cars ("F  Mission board",
## "F  Ride out: <mission>", "F  Ride home"), and the chosen mission in the top left.

var missions: Node
var player: Node3D

var _label: Label
var _mission: Label


func _ready() -> void:
	layer = 4
	_label = _make(17, Color(0.95, 0.93, 0.85))
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_label.position += Vector2(-160, 64)
	_label.custom_minimum_size = Vector2(320, 24)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mission = _make(15, Color(0.85, 0.7, 0.42))
	_mission.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_mission.position = Vector2(24, 20)
	_mission.add_theme_font_size_override(&"font_size", 17)


func _make(size: int, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", colour)
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override(&"outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		queue_free()
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var current: Dictionary = missions.get(&"current")
	var state := str(missions.get(&"state"))
	match str(missions.call(&"facing", player)) if captured else "":
		"board":
			_label.text = "F   Mission board"
		"ride_out":
			if current.is_empty():
				_label.text = "Choose a mission at the board first"
			elif state != "home":
				_label.text = "A run is already on"
			else:
				_label.text = "F   Ride out: %s" % current.get("name", "")
		"ride_home":
			_label.text = "F   Ride home"
		_:
			_label.text = ""
	_label.visible = not _label.text.is_empty()
	if current.is_empty():
		_mission.text = ""
	else:
		var where := "out on" if state != "home" else "chosen:"
		_mission.text = "Mission %s %s  ·  %d m  ·  %d kr" % [where, current.get("name", ""), int(current.get("distance", 0)), int(current.get("payout", 0))]
	_mission.visible = captured and not _mission.text.is_empty()

class_name MissionPrompt
extends CanvasLayer
## Client only, local player: what the interact key does at the board and the cars
## ("Mission board", "Ride out: <mission>", "Ride home"), as a line on the prompt stack, and
## the chosen mission in the top left.

var missions: Node
var player: Node3D

var _mission: Label


func _ready() -> void:
	layer = UiLayers.PROMPTS
	_mission = Label.new()
	_mission.theme_type_variation = &"HudLabel"
	_mission.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mission.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_mission.position = Vector2(24, 20)
	_mission.add_theme_color_override(&"font_color", UiPalette.ACCENT)
	add_child(_mission)


func _exit_tree() -> void:
	PromptStack.of(get_tree()).clear_line(&"mission")


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		queue_free()
		return
	var prompts := PromptStack.of(get_tree())
	var current: Dictionary = missions.get(&"current")
	var state := str(missions.get(&"state"))
	var action := &"interact"
	var what := ""
	if missions.call(&"disarmable", player) != null:
		what = "Disarm"
	else:
		match str(missions.call(&"facing", player)):
			"board":
				what = "Mission board"
			"ride_out":
				if current.is_empty():
					action = &""
					what = "Choose a mission at the board first"
				elif state != "home":
					action = &""
					what = "A run is already on"
				else:
					what = "Ride out: %s" % current.get("codename", "")
			"ride_home":
				what = "Ride home"
	if what.is_empty():
		prompts.clear_line(&"mission")
	else:
		prompts.set_line(&"mission", action, what, 2)
	var lines: Array[String] = ["Tokens: %d" % int(missions.get(&"my_tokens"))]
	if not current.is_empty() and state == "home":
		lines.append("Mission chosen: %s (%s)  ·  %d m  ·  %d tokens" % [current.get("codename", ""), current.get("type_name", ""), int(current.get("distance", 0)), int(current.get("payout", 0))])
	elif not current.is_empty():
		lines.append("%s  ·  %s" % [current.get("codename", ""), current.get("type_name", "")])
		for line: Variant in missions.call(&"hud_lines", player):
			lines.append(str(line))
	_mission.text = "\n".join(lines)
	_mission.visible = not UiStack.is_blocking()

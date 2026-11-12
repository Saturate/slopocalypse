extends "res://trailer/shots/stage.gd"
## Trailer shot: home base. The camera glides down the tunnel past the mission board to the
## transport car waiting further in.

const EYE := 1.6
const GLIDE := 330

var _end := Vector3.ZERO
var _car := Vector3.ZERO


func _modules() -> Array[String]:
	return ["inventory", "missions"]


func _setup() -> void:
	keep_above_ground = false
	player.set_physics_process(false)
	player.visible = false


func _place() -> void:
	var floor_y := (get_tree().get_first_node_in_group(&"spawn_point") as Node3D).global_position.y
	var board_node := mission().get_node("MissionBoard") as Node3D
	var board := board_node.global_position
	# The side the board's face is on.
	var facing := -board_node.global_basis.z
	var car := (mission().get_node("Transport") as Node3D).global_position
	var along := car - board
	along.y = 0.0
	along = along.normalized()
	# In front of the board's face and back along the tunnel, turned to it at an angle.
	var start := board + facing * 2.6 - along * 2.5
	start.y = floor_y + EYE
	frame(start, board)
	var end := car - along * 5.0 + facing * 1.2
	end.y = floor_y + EYE - 0.2
	_end = end
	_car = car


func _shot(t: int) -> void:
	if t == 1:
		move_to(_end, _car + Vector3.UP * 0.6, GLIDE)

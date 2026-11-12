extends "res://trailer/shots/stage.gd"
## Trailer shot: a player opens fire on soldiers holding a house. They shout, duck into cover
## and shoot back; one, alone and hurt, throws down his gun. Camera starts over the player's
## shoulder and slides out to the side to show both.

const OPEN_FIRE := 30
## Ticks of trigger held, then released, in bursts.
const BURST := [14, 26]
const SLIDE_AT := 20
const GIVE_UP_AT := 260
## How far in front of the house the player stands.
const STAND_OFF := 14.0

var _building: Node3D
var _stand := Vector3.ZERO
var _front := Vector3.FORWARD


func _setup() -> void:
	start_mission("clean_sweep")
	(player.get_node("Health") as HealthComponent).invulnerable = true


func _place() -> void:
	subject_body = (mission().call(&"building_nodes") as Array)[0]
	var intent: PlayerIntent = player.call(&"intent")
	_building = (mission().call(&"building_nodes") as Array)[0]
	_front = -_building.global_basis.z
	var d := float(_building.get(&"spec")["depth"])
	_stand = _building.global_position + _front * (d / 2.0 + STAND_OFF)
	_stand.y = ground_y(_stand.x, _stand.z) + 0.1
	player.global_position = _stand
	intent.crouch = true
	var side := _front.cross(Vector3.UP).normalized()
	var look := _building.global_position + Vector3.UP * 1.4
	frame(_stand + _front * 2.4 + side * 0.8 + Vector3.UP * 1.5, look)
	var w := float(_building.get(&"spec")["width"])
	var corner := _building.global_position + _front * (d / 2.0 + 2.5) + side * (w / 2.0 + 4.5)
	clear_line(_stand + _front * 3.0, _building.global_position, 4.0)
	clear_line(corner, _stand, 4.0)


func _shot(t: int) -> void:
	var intent: PlayerIntent = player.call(&"intent")
	var target := _nearest_guard()
	if target != null:
		_aim(intent, target.global_position + Vector3.UP * 1.3)
	if t >= OPEN_FIRE and target != null:
		var phase := (t - OPEN_FIRE) % (BURST[0] + BURST[1])
		intent.fire = phase < BURST[0]
	if t == SLIDE_AT:
		var side := _front.cross(Vector3.UP).normalized()
		# Out beside the house's front corner, looking back along the line of fire.
		var d := float(_building.get(&"spec")["depth"])
		var w := float(_building.get(&"spec")["width"])
		var corner := _building.global_position + _front * (d / 2.0 + 2.5) + side * (w / 2.0 + 4.5)
		corner.y = ground_y(corner.x, corner.z) + 1.4
		var between := _stand.lerp(_building.global_position, 0.45) + Vector3.UP * 1.0
		move_to(corner, between, 260)
	if t == GIVE_UP_AT and target != null:
		# Alone and wounded he breaks: low nerve and a hit put him in the submit band.
		var brain := target.get_node("Brain")
		brain.set(&"fortitude_start", 2)
		(target.get_node("Health") as HealthComponent).server_apply_damage(40.0)


func _aim(intent: PlayerIntent, at: Vector3) -> void:
	var eye := player.global_position + Vector3.UP * 1.5
	var dir := (at - eye).normalized()
	intent.remote_look = true
	intent.look_yaw = atan2(-dir.x, -dir.z)
	intent.look_pitch = asin(clampf(dir.y, -1.0, 1.0))


## The closest soldier still fighting.
func _nearest_guard() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var e := node as Node3D
		if e == null or e.get_meta(&"surrendered", false) or e.get_meta(&"dead", false):
			continue
		var d := e.global_position.distance_to(_stand)
		if d < best_d:
			best_d = d
			best = e
	return best

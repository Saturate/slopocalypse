extends "res://trailer/shots/stage.gd"
## Trailer shot: a strike zone house takes three diving drones along its lower walls and comes
## down. Low camera pushing in slowly from across the road.

## Ticks at which each drone is sent in, and where on the front wall it aims (x across the
## wall from -0.5 to 0.5, height in metres).
const DRONES := [[20, -0.32, 0.7], [80, 0.3, 0.7], [140, 0.0, 0.9], [175, -0.05, 2.0]]
## How far out in front and above the aim point a drone starts its dive.
const DIVE_FROM := Vector3(0.0, 9.0, 16.0)
## Ticks after a dive starts by which it has surely hit; if it has not, the blast goes off
## anyway so the shot stays on time.
const DIVE_TIMEOUT := 120

var _building: Node3D
var _front := Vector3.FORWARD
var _side := Vector3.RIGHT
var _sent := {}
var _end := Vector3.ZERO
var _look := Vector3.ZERO


func _modules() -> Array[String]:
	return ["weapons", "inventory", "enemies", "drones", "missions"]


func _setup() -> void:
	start_mission("smash_and_grab")
	(player.get_node("Health") as HealthComponent).invulnerable = true


func _place() -> void:
	subject_body = _pick_building()
	_building = _pick_building()
	_front = -_building.global_basis.z
	_side = _building.global_basis.x
	var d := float(_building.get(&"spec")["depth"])
	var centre := _building.global_position + Vector3.UP * 1.6
	var face := _building.global_position + _front * (d / 2.0)
	# Out of the way, behind the camera.
	player.global_position = face + _front * 60.0 + Vector3.UP * 2.0
	player.set_physics_process(false)
	var start := face + _front * 21.0 + _side * 5.0
	start.y = ground_y(start.x, start.z) + 1.4
	frame(start, centre)
	_end = face + _front * 14.0 + _side * 2.5
	_end.y = ground_y(_end.x, _end.z) + 1.1
	_look = centre + Vector3.UP * 0.6
	clear_line(start, face, 4.0)
	clear_line(_end, face, 4.0)


func _shot(t: int) -> void:
	if t == 1:
		move_to(_end, _look, 420)
	for i in DRONES.size():
		var spec: Array = DRONES[i]
		if t == int(spec[0]):
			_send(i, float(spec[1]), float(spec[2]))
		elif _sent.has(i) and t == int(spec[0]) + DIVE_TIMEOUT:
			var drone: Variant = _sent[i]["drone"]
			if is_instance_valid(drone):
				(drone as Node).call(&"server_detonate", 3.0, 80.0)


func _send(i: int, across: float, height: float) -> void:
	var spec: Dictionary = _building.get(&"spec")
	var w := float(spec["width"])
	var d := float(spec["depth"])
	var aim := _building.global_transform * Vector3(across * w, 0.0, -d / 2.0 - 0.6)
	aim.y = _building.global_position.y + height - 1.1
	var drones: Node = modules["drones"]
	var drone: Node3D = drones.call(&"server_spawn_strike", aim)
	drone.global_position = aim + _front * DIVE_FROM.z + Vector3.UP * DIVE_FROM.y + _side * (across * 6.0)
	drone.call(&"server_dive")
	_sent[i] = {"drone": drone}


## The wooden house nearest the road, so the blasts open it up rather than chip concrete.
func _pick_building() -> Node3D:
	var all: Array = mission().call(&"building_nodes")
	for b: Node3D in all:
		if float((b.get(&"material_cfg") as Dictionary).get("hole", 0.0)) > 0.0:
			return b
	return all[0]

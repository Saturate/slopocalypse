extends "res://trailer/shots/stage.gd"
## Trailer shot: over the shoulder, a player sticks a breaching charge on a wooden wall, backs
## off, and it blows a hole through. No drones loaded, so nothing else goes off in frame.

const PLACE_AT := 40
const BACK_OFF := [75, 165]
const BLOW_AT := 215
## Where on the side wall the charge goes, metres up.
const CHARGE_HEIGHT := 1.0

var _building: Node3D
var _wall_point := Vector3.ZERO
var _out := Vector3.RIGHT
var _side := Vector3.FORWARD
var _charge: Node


func _modules() -> Array[String]:
	return ["weapons", "inventory", "enemies", "missions"]


func _setup() -> void:
	start_mission("smash_and_grab")
	(player.get_node("Health") as HealthComponent).invulnerable = true


func _place() -> void:
	subject_body = _pick_building()
	_building = _pick_building()
	var spec: Dictionary = _building.get(&"spec")
	var w := float(spec["width"])
	_out = _building.global_basis.x
	_wall_point = _building.global_transform * Vector3(w / 2.0, 0.0, 0.0)
	_wall_point.y = ground_y(_wall_point.x, _wall_point.z) + CHARGE_HEIGHT
	var stand := _wall_point + _out * 1.3
	stand.y = ground_y(stand.x, stand.z) + 0.1
	player.global_position = stand
	face(_wall_point)
	_side = _out.cross(Vector3.UP).normalized()
	# Over the right shoulder, a little low, so the wall fills the frame.
	frame(stand + _out * 2.8 + _side * 1.0 + Vector3.UP * 1.7, _wall_point + Vector3.UP * 0.3)
	clear_line(_wall_point + _out * 1.0, _wall_point + _out * 6.0 + _side * 3.0, 3.5)


func _shot(t: int) -> void:
	var intent: PlayerIntent = player.call(&"intent")
	if t == 1:
		var stand := player.global_position
		move_to(stand + _out * 2.2 + _side * 0.8 + Vector3.UP * 1.6, _wall_point + Vector3.UP * 0.2, PLACE_AT)
	elif t == PLACE_AT:
		var stats: Dictionary = (Data.load_json("res://modules/weapons/data/weapons.json") as Dictionary)["charge"]
		stats = stats.duplicate()
		stats["remote"] = true
		_charge = modules["weapons"].call(&"spawn_charge", _wall_point + _out * 0.06, stats)
	elif t == BACK_OFF[0]:
		intent.move = Vector2(0.0, -1.0)
		# Swing out to the side as the player backs off, to see the wall and the player.
		move_to(_wall_point + _out * 5.5 + _side * 2.8 + Vector3.UP * 0.9, _wall_point + _out * 1.8, BACK_OFF[1] - BACK_OFF[0] + 40)
	elif t == BACK_OFF[1]:
		intent.move = Vector2.ZERO
		intent.crouch = true
	elif t == BLOW_AT and is_instance_valid(_charge):
		_charge.call(&"server_explode")


func _pick_building() -> Node3D:
	var all: Array = mission().call(&"building_nodes")
	for b: Node3D in all:
		if float((b.get(&"material_cfg") as Dictionary).get("hole", 0.0)) > 0.0:
			return b
	return all[0]

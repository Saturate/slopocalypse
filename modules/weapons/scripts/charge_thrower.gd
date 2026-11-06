class_name ChargeThrower
extends Node
## Lets a player place demolition charges where they aim. Reads the holder's PlayerIntent;
## the server decides where the charge lands.

const CONFIG := "res://modules/weapons/data/weapons.json"
const REQUIRED := {"fuse_seconds": TYPE_FLOAT, "radius": TYPE_FLOAT, "damage": TYPE_FLOAT, "range": TYPE_FLOAT, "cooldown_seconds": TYPE_FLOAT}

var holder: PlayerController
## Where placed charges live in the scene tree.
var charges_parent: Node

var stats: Dictionary = {}
var _cooldown := 0.0


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not (data as Dictionary).has("charge") or not Data.require(CONFIG + " charge", data["charge"], REQUIRED):
		set_physics_process(false)
		return
	stats = data["charge"]


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if holder.intent().consume_throw() and multiplayer.is_server():
		var camera: Camera3D = holder.get_node("Head/Camera")
		server_place(camera.global_position, -camera.global_transform.basis.z)


## Server only: drops a charge on the first surface along the aim, within range.
func server_place(origin: Vector3, direction: Vector3) -> DemolitionCharge:
	if _cooldown > 0.0:
		return null
	var to := origin + direction.normalized() * float(stats["range"])
	var query := PhysicsRayQueryParameters3D.create(origin, to, 0xFFFFFFFF, [holder.get_rid()])
	var hit := holder.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	_cooldown = stats["cooldown_seconds"]
	var charge := DemolitionCharge.new()
	charge.stats = stats
	charge.owner_player = holder
	charges_parent.add_child(charge)
	charge.global_position = hit["position"]
	return charge

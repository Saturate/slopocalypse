class_name ChargeThrower
extends Node
## Lets a player place charges where they aim. Reads the holder's PlayerIntent; the server
## decides where the charge lands. With the inventory loaded a charge is an item: placing
## one uses up a breaching charge from the holder's gear, it sticks where it lands, and it
## waits for the holder to set it off (`detonate`, all of theirs at once). Without the
## inventory it is the old fused demolition charge.

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
	var prof := Prof.start()
	_physics_tick(delta)
	Prof.stop(&"weapons/charge_thrower:physics", prof)


func _physics_tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if holder.intent().consume_throw() and multiplayer.is_server():
		var camera: Camera3D = holder.get_node("Head/Camera")
		server_place(camera.global_position, -camera.global_transform.basis.z)
	if holder.intent().consume_detonate() and multiplayer.is_server():
		server_detonate()


func _inventory() -> Node:
	return get_tree().get_first_node_in_group(&"inventory_api") if is_inside_tree() else null


## Server only: sets off every charge this holder placed.
func server_detonate() -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group(&"charges"):
		var charge := node as DemolitionCharge
		if charge != null and charge.owner_player == holder and not charge.is_queued_for_deletion():
			charge.server_explode()
			count += 1
	return count


## Server only: drops a charge on the first surface along the aim, within range.
func server_place(origin: Vector3, direction: Vector3) -> DemolitionCharge:
	if _cooldown > 0.0:
		return null
	var to := origin + direction.normalized() * float(stats["range"])
	var query := PhysicsRayQueryParameters3D.create(origin, to, 0xFFFFFFFF, [holder.get_rid()])
	var hit := holder.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var used := stats.duplicate()
	var inv := _inventory()
	if inv != null:
		var peer := int(holder.get_meta(&"peer_id", 1))
		if not inv.call(&"server_take", peer, str(stats.get("item", "breach_charge"))):
			return null
		used["remote"] = true
	_cooldown = stats["cooldown_seconds"]
	var at: Vector3 = hit["position"]
	# The weapons module replicates charges to clients; tests hand in a plain parent.
	var charge: DemolitionCharge
	if charges_parent.has_method(&"spawn_charge"):
		charge = charges_parent.call(&"spawn_charge", at, used)
	else:
		charge = DemolitionCharge.new()
		charge.stats = used
		charges_parent.add_child(charge)
		charge.global_position = at
	charge.owner_player = holder
	return charge

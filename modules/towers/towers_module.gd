extends Node
## Water towers at the map's tower sites whose tanks leak where they are shot (WaterTower). The server
## decides which rounds hole a tank and broadcasts `towers.holed`; every machine drains the
## same tank from the holes, and someone joining later is sent the holes with their ages.

const CONFIG := "res://modules/towers/data/towers.json"
const REQUIRED := {"tower": TYPE_DICTIONARY, "sites": TYPE_ARRAY}

var config: Dictionary = {}
var towers: Array[WaterTower] = []
## Holes heard of before the towers stood (a late joiner): tower id -> snapshot.
var _waiting: Dictionary[int, Array] = {}


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not (data is Dictionary and Data.require(CONFIG, data, REQUIRED)):
		return
	config = data
	EventBus.subscribe(&"world.ready", _on_world_ready)
	EventBus.subscribe(&"weapon.fired", _on_weapon_fired)
	EventBus.subscribe(&"towers.holed", _on_holed)
	Net.peer_joined.connect(_on_peer_joined)
	add_to_group(&"world_state")


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
	EventBus.unsubscribe(&"weapon.fired", _on_weapon_fired)
	EventBus.unsubscribe(&"towers.holed", _on_holed)
	if Net.peer_joined.is_connected(_on_peer_joined):
		Net.peer_joined.disconnect(_on_peer_joined)


func _on_world_ready(_p: Dictionary) -> void:
	if not towers.is_empty():
		return
	# The map has water-tower sites by its farms and towns (#472); the flat test world none.
	var ground := get_tree().get_first_node_in_group(&"ground")
	if ground == null or not ground.has_method(&"map_sites"):
		return
	var spots: Array[Transform3D] = []
	# Kinds in the order the data lists them, so every machine numbers the towers alike.
	for kind: Variant in config["sites"]:
		for at: Vector3 in ground.call(&"map_sites", str(kind)):
			spots.append(Transform3D(Basis.IDENTITY, at))
	place(spots)


## Everywhere: a tower at each spot, numbered in order.
func place(spots: Array[Transform3D]) -> void:
	for spot in spots:
		var tower := WaterTower.new()
		tower.tower_id = towers.size()
		tower.name = "Tower%d" % tower.tower_id
		tower.config = config.get("tower", {})
		tower.transform = spot
		add_child(tower)
		towers.append(tower)
		if _waiting.has(tower.tower_id):
			tower.catch_up(_waiting[tower.tower_id])
			_waiting.erase(tower.tower_id)


func tower(id: int) -> WaterTower:
	return towers[id] if id >= 0 and id < towers.size() and is_instance_valid(towers[id]) else null


func _on_weapon_fired(p: Dictionary) -> void:
	if not multiplayer.is_server() or not p.has("to"):
		return
	var hit := p.get("collider") as WaterTower
	if hit == null or not towers.has(hit):
		return
	var at := hit.tank_hit(p["to"])
	if at.is_empty():
		return
	Net.server_broadcast(&"towers.holed", {"id": hit.tower_id, "point": at["point"], "normal": at["normal"]})


func _on_holed(p: Dictionary) -> void:
	var it := tower(int(p["id"]))
	if it != null:
		it.add_hole(p["point"], p["normal"])


func _on_peer_joined(peer: int) -> void:
	if not multiplayer.is_server() or not multiplayer.get_peers().has(peer):
		return
	var state: Dictionary = {}
	for t in towers:
		var holes := t.snapshot()
		if not holes.is_empty():
			state[t.tower_id] = holes
	if not state.is_empty():
		_sync.rpc_id(peer, state)


## Late joiner: the holes in each tower so far, with their ages.
@rpc("authority", "call_remote", "reliable")
func _sync(state: Dictionary) -> void:
	apply_snapshot(state)


func apply_snapshot(state: Dictionary) -> void:
	for key: Variant in state:
		var id := int(key)
		var it := tower(id)
		if it != null:
			it.catch_up(state[key])
		else:
			_waiting[id] = state[key]


## The `world_state` contract (persistence): holes stay holed and tanks stay drained across
## restarts (the time the server was off doesn't count).
func world_state_owner() -> String:
	return "towers"


func world_state_version() -> int:
	return 1


func server_world_state() -> Dictionary:
	var state: Dictionary = {}
	for t in towers:
		var holes := t.snapshot()
		if not holes.is_empty():
			state[t.tower_id] = holes
	return state


func server_restore_world_state(version: int, data: Variant) -> void:
	if version == 1 and data is Dictionary:
		apply_snapshot(data)

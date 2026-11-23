extends Node
## Lights: street lamps along the highway out of the camp's gate and wherever another
## module asks for them (`city.lamp_spots`: {spots: Array[Transform3D]}), whose bulbs glow,
## light the street and shatter when shot, and a budget that keeps only the nearest lights
## real on each screen (LightBudget).
##
## The server decides which bulbs are broken: a round on a bulb broadcasts
## `lights.lamp_broken`, and someone joining later is told which are already out.

const CONFIG := "res://modules/lights/data/lights.json"
const REQUIRED := {"budget": TYPE_DICTIONARY, "lamp": TYPE_DICTIONARY, "road": TYPE_DICTIONARY}

var config: Dictionary = {}
var lamps: Array[StreetLamp] = []
## Lamp id -> true, for every bulb broken so far (also those not placed yet here).
var _broken: Dictionary[int, bool] = {}


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not (data is Dictionary and Data.require(CONFIG, data, REQUIRED)):
		return
	config = data
	if DisplayServer.get_name() != "headless":
		var budget := LightBudget.new()
		budget.name = "Budget"
		var b: Dictionary = config["budget"]
		budget.max_shadow = 0 if RenderSwitches.no_shadows(OS.get_cmdline_user_args()) else int(b.get("max_shadow_lights", 4))
		budget.max_lit = int(b.get("max_lights", 16))
		budget.fade = float(b.get("fade_seconds", 0.3))
		add_child(budget)
	EventBus.subscribe(&"world.ready", _on_world_ready)
	EventBus.subscribe(&"city.lamp_spots", _on_lamp_spots)
	EventBus.subscribe(&"weapon.fired", _on_weapon_fired)
	EventBus.subscribe(&"lights.lamp_broken", _on_lamp_broken)
	Net.peer_joined.connect(_on_peer_joined)
	add_to_group(&"world_state")


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
	EventBus.unsubscribe(&"city.lamp_spots", _on_lamp_spots)
	EventBus.unsubscribe(&"weapon.fired", _on_weapon_fired)
	EventBus.unsubscribe(&"lights.lamp_broken", _on_lamp_broken)
	if Net.peer_joined.is_connected(_on_peer_joined):
		Net.peer_joined.disconnect(_on_peer_joined)


func _on_world_ready(_p: Dictionary) -> void:
	if not lamps.is_empty():
		return
	var ground := get_tree().get_first_node_in_group(&"ground")
	if ground == null or not ground.has_method(&"road_point"):
		return
	var height := func(x: float, z: float) -> float:
		return float(ground.call(&"surface_height" if ground.has_method(&"surface_height") else &"ground_height", x, z))
	place(road_spots(func(m: float) -> Vector3: return ground.call(&"road_point", m), height, config["road"]))


## Lamps somewhere else in the world (the city's streets). Every machine hears this in the
## same order as the road's, so lamp ids match.
func _on_lamp_spots(p: Dictionary) -> void:
	var spots: Array[Transform3D] = []
	for spot: Variant in p.get("spots", []):
		if spot is Transform3D:
			spots.append(spot)
	place(spots)


## Where street lamps stand along a road given as `road_at(metres) -> point`: alternating
## sides, each turned so its arm reaches out over the road.
static func road_spots(road_at: Callable, height_at: Callable, road: Dictionary) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for i in int(road.get("count", 0)):
		var m := float(road.get("first", 20.0)) + float(i) * float(road.get("spacing", 30.0))
		var centre: Vector3 = road_at.call(m)
		var along: Vector3 = (road_at.call(m + 1.0) as Vector3) - centre
		along.y = 0.0
		if along.length() < 0.001:
			along = Vector3.FORWARD
		var right := along.normalized().cross(Vector3.UP)
		var side := 1.0 if i % 2 == 0 else -1.0
		var at := centre + right * side * float(road.get("side", 5.0))
		at.y = float(height_at.call(at.x, at.z))
		var toward := -right * side
		out.append(Transform3D(Basis(Vector3.UP, atan2(-toward.z, toward.x)), at))
	return out


## Everywhere: puts up a lamp at each spot, numbered in order, with any already broken out.
func place(spots: Array[Transform3D]) -> void:
	for spot in spots:
		var lamp := StreetLamp.new()
		lamp.lamp_id = lamps.size()
		lamp.name = "Lamp%d" % lamp.lamp_id
		lamp.config = config.get("lamp", {})
		lamp.transform = spot
		add_child(lamp)
		lamps.append(lamp)
		if _broken.has(lamp.lamp_id):
			lamp.break_bulb(false)


func lamp(id: int) -> StreetLamp:
	return lamps[id] if id >= 0 and id < lamps.size() and is_instance_valid(lamps[id]) else null


func _on_weapon_fired(p: Dictionary) -> void:
	if not multiplayer.is_server() or not p.has("to"):
		return
	var hit := p.get("collider") as StreetLamp
	if hit != null and lamps.has(hit) and hit.hits_bulb(p["to"]):
		Net.server_broadcast(&"lights.lamp_broken", {"id": hit.lamp_id})


func _on_lamp_broken(p: Dictionary) -> void:
	var id := int(p["id"])
	_broken[id] = true
	var it := lamp(id)
	if it != null:
		it.break_bulb(true)


func _on_peer_joined(peer: int) -> void:
	if multiplayer.is_server() and not _broken.is_empty() and multiplayer.get_peers().has(peer):
		_sync.rpc_id(peer, _broken.keys())


## Late joiner: these bulbs were already out.
@rpc("authority", "call_remote", "reliable")
func _sync(ids: Array) -> void:
	apply_broken(ids)


func apply_broken(ids: Array) -> void:
	for v: Variant in ids:
		var id := int(v)
		_broken[id] = true
		var it := lamp(id)
		if it != null:
			it.break_bulb(false)


## The `world_state` contract (persistence): shot-out bulbs stay out across restarts.
func world_state_owner() -> String:
	return "lights"


func world_state_version() -> int:
	return 1


func server_world_state() -> Array:
	return _broken.keys()


func server_restore_world_state(version: int, data: Variant) -> void:
	if version == 1 and data is Array:
		apply_broken(data)

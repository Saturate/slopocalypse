extends Node
## Home base and the mission run. The start tunnel is home: a mission board on the wall
## offers a few missions, and the car parked inside rides everyone at home out to the chosen
## mission's drop-off point down the road; the car waiting there rides them back. The server
## owns the run (`home`, then `in_mission` until nobody is out any more) and tells everyone
## through `missions.*` topics. Mission content (objective, drones, pay) comes in later
## issues; this is the flow.

const CONFIG := "res://modules/missions/data/missions.json"
const REQUIRED := {
	"home_radius": TYPE_FLOAT, "reach": TYPE_FLOAT, "ride_fade_seconds": TYPE_FLOAT,
	"ride_home_reach": TYPE_FLOAT, "drop_spread": TYPE_FLOAT, "board": TYPE_DICTIONARY,
	"transport": TYPE_DICTIONARY, "dropoff_side": TYPE_FLOAT, "offered": TYPE_FLOAT,
	"seed": TYPE_FLOAT, "missions": TYPE_ARRAY,
}
## How squarely you must face the board or a car to use it.
const FACING := 0.7
const HOME := "home"
const IN_MISSION := "in_mission"

var config: Dictionary = {}
## Everywhere: the offered missions, the chosen one (or empty) and the run state, as the
## server last said.
var offers: Array = []
var current: Dictionary = {}
var state := HOME

var _spawn := Vector3.ZERO
var _board: MissionBoard
var _transport: TransportCar
var _dropoff_car: TransportCar
## The mission the drop-off car stands for (the server sets `current` before it hears its
## own broadcast, so compare with this instead).
var _placed_for: Dictionary = {}
## Server: peers out on the mission; how many runs have ended (rolls the next offers).
var _out: Dictionary = {}
var _runs := 0


func _ready() -> void:
	add_to_group(&"missions_api")
	var parsed: Variant = Data.load_json(CONFIG)
	if not parsed is Dictionary or not Data.require(CONFIG, parsed, REQUIRED):
		return
	config = parsed
	offers = roll_offers(config, int(config["seed"]))
	EventBus.subscribe(&"world.ready", _on_world_ready)
	EventBus.subscribe(&"player.interact", _on_player_interact)
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	EventBus.subscribe(&"player.respawned", _on_player_respawned)
	EventBus.subscribe(&"missions.changed", _on_changed)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
	EventBus.unsubscribe(&"player.interact", _on_player_interact)
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)
	EventBus.unsubscribe(&"player.respawned", _on_player_respawned)
	EventBus.unsubscribe(&"missions.changed", _on_changed)
	if Net.peer_joined.is_connected(_on_peer_joined):
		Net.peer_joined.disconnect(_on_peer_joined)
	if Net.peer_left.is_connected(_on_peer_left):
		Net.peer_left.disconnect(_on_peer_left)


## `count` missions rolled from the config's list with `seed`: each picks a template (no
## repeats while there are enough) and rolls its distance and payout in the template's
## ranges.
static func roll_offers(cfg: Dictionary, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var templates: Array = (cfg.get("missions", []) as Array).duplicate()
	var out := []
	for i in int(cfg.get("offered", 3)):
		if templates.is_empty():
			templates = (cfg.get("missions", []) as Array).duplicate()
		if templates.is_empty():
			break
		var t: Dictionary = templates.pop_at(rng.randi_range(0, templates.size() - 1))
		var d: Array = t.get("distance", [200.0, 300.0])
		var pay: Array = t.get("payout", [100.0, 200.0])
		out.append({
			"id": t.get("id", ""),
			"name": t.get("name", ""),
			"objective": t.get("objective", ""),
			"distance": snappedf(rng.randf_range(float(d[0]), float(d[1])), 10.0),
			"time_limit": float(t.get("time_limit", 180.0)),
			"payout": snappedf(rng.randf_range(float(pay[0]), float(pay[1])), 10.0),
		})
	return out


## Where a mission drops the group off: beside the road `distance` metres out.
func dropoff_of(mission: Dictionary) -> Vector3:
	var at := Vector3(0.0, 0.0, -float(mission.get("distance", 0.0)))
	var ground := get_tree().get_first_node_in_group(&"ground")
	if ground != null and ground.has_method(&"road_point"):
		at = ground.call(&"road_point", float(mission.get("distance", 0.0)))
	at.x += float(config.get("dropoff_side", 0.0))
	if ground != null and ground.has_method(&"ground_height"):
		at.y = float(ground.call(&"ground_height", at.x, at.z))
	return at


func _on_world_ready(payload: Dictionary) -> void:
	_spawn = payload.get("spawn", Vector3.ZERO)
	_board = MissionBoard.new()
	_board.name = "MissionBoard"
	add_child(_board)
	_board.global_position = _home_point(config["board"])
	_board.rotation.y = PI / 2.0 if float((config["board"]["offset"] as Array)[0]) > 0.0 else -PI / 2.0
	_transport = TransportCar.new()
	_transport.name = "Transport"
	add_child(_transport)
	_transport.global_position = _home_point(config["transport"])
	_place_dropoff_car()


## A spot in the tunnel `offset` from the spawn, on its floor.
func _home_point(entry: Dictionary) -> Vector3:
	var o: Array = entry.get("offset", [0.0, 0.0, 0.0])
	var at := _spawn + Vector3(float(o[0]), float(o[1]), float(o[2]))
	# The spawn marker floats a metre over the floor.
	at.y = _spawn.y - 1.0 + float(o[1])
	return at


func _place_dropoff_car() -> void:
	_placed_for = current
	if _dropoff_car != null:
		_dropoff_car.queue_free()
		_dropoff_car = null
	if current.is_empty() or not is_inside_tree():
		return
	_dropoff_car = TransportCar.new()
	_dropoff_car.name = "DropoffCar"
	add_child(_dropoff_car)
	_dropoff_car.global_position = dropoff_of(current)


## What `player` is looking at among the board and the two cars: "board", "ride_out",
## "ride_home" or "".
func facing(player: Node3D) -> String:
	var head := player.get_node_or_null("Head/Camera") as Node3D
	var eye := head.global_position if head != null else player.global_position + Vector3.UP * 1.6
	var forward := -head.global_transform.basis.z if head != null else -player.global_transform.basis.z
	var reach := float(config.get("reach", 2.6))
	var best := ""
	var best_facing := FACING
	for entry: Array in [[_board, "board", 1.2], [_transport, "ride_out", 0.9], [_dropoff_car, "ride_home", 0.9]]:
		var node := entry[0] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var to: Vector3 = node.global_position + Vector3.UP * float(entry[2]) - eye
		var f := forward.dot(to.normalized())
		# A car is long: measure to its nearest end, roughly.
		if to.length() < reach + 1.5 and f > best_facing:
			best = entry[1]
			best_facing = f
	return best


func is_home(player: Node3D) -> bool:
	return player.global_position.distance_to(_spawn) < float(config.get("home_radius", 26.0))


## Server: F at the board opens it (for that player); at the parked car with a mission
## chosen it rides everyone at home out; at the drop-off car it rides those near it home.
func _on_player_interact(payload: Dictionary) -> void:
	if not multiplayer.is_server() or payload.get("handled", false):
		return
	var player := payload["player"] as Node3D
	var peer := int(player.get_meta(&"peer_id", 1))
	match facing(player):
		"board":
			payload["handled"] = true
			_show_board(peer)
		"ride_out":
			payload["handled"] = true
			server_ride_out()
		"ride_home":
			payload["handled"] = true
			server_ride_home(player)


func _show_board(peer: int) -> void:
	if peer == multiplayer.get_unique_id():
		EventBus.publish(&"missions.board_opened", {"peer": peer})
	elif multiplayer.get_peers().has(peer):
		_open_board.rpc_id(peer)


@rpc("authority", "call_remote", "reliable")
func _open_board() -> void:
	EventBus.publish(&"missions.board_opened", {"peer": multiplayer.get_unique_id()})


## Client: picks offer `index` from the board.
func request_choose(index: int) -> void:
	if multiplayer.is_server():
		server_choose(multiplayer.get_unique_id(), index)
	else:
		_request_choose.rpc_id(1, index)


@rpc("any_peer", "call_remote", "reliable")
func _request_choose(index: int) -> void:
	if multiplayer.is_server():
		server_choose(multiplayer.get_remote_sender_id(), index)


## Server: makes offer `index` the mission, for everyone. Refused while a run is on.
func server_choose(peer: int, index: int) -> bool:
	if state != HOME:
		EventBus.publish(&"missions.refused", {"peer": peer, "reason": "a run is on"})
		return false
	if index < 0 or index >= offers.size():
		EventBus.publish(&"missions.refused", {"peer": peer, "reason": "no such mission"})
		return false
	current = offers[index]
	EventBus.publish(&"missions.chosen", {"peer": peer, "mission": current.get("id", "")})
	_broadcast()
	return true


## Server: everyone at home rides out to the chosen mission's drop-off. False if there is no
## mission or a run is already on.
func server_ride_out() -> bool:
	if current.is_empty() or state != HOME:
		return false
	var at := dropoff_of(current)
	var riders: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Node3D
		if player != null and not player.get_meta(&"dead", false) and is_home(player):
			riders.append(player)
	if riders.is_empty():
		return false
	state = IN_MISSION
	var spread := float(config.get("drop_spread", 2.0))
	for i in riders.size():
		var player := riders[i]
		_out[int(player.get_meta(&"peer_id", 1))] = true
		# Line up beside the car, not on top of each other.
		var spot := at + Vector3(-1.5 - spread * (i % 3), 0.5, spread * (i / 3) - 1.0)
		EventBus.publish(&"player.move_requested", {"player": player, "position": spot})
	EventBus.publish(&"missions.started", {"mission": current.get("id", ""), "riders": _out.keys()})
	_broadcast(_out.keys())
	return true


## Server: everyone within reach of the drop-off car (who is out) rides home with
## `player`. The run ends once nobody is out any more.
func server_ride_home(player: Node3D) -> bool:
	if state != IN_MISSION or _dropoff_car == null:
		return false
	var reach := float(config.get("ride_home_reach", 14.0))
	var riders: Array = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var p := node as Node3D
		var peer := int(p.get_meta(&"peer_id", 1)) if p != null else 0
		if p == null or not _out.has(peer) or p.get_meta(&"dead", false):
			continue
		if p.global_position.distance_to(_dropoff_car.global_position) <= reach:
			riders.append(peer)
			_out.erase(peer)
			var spread := float(config.get("drop_spread", 2.0))
			EventBus.publish(&"player.move_requested", {"player": p, "position": _spawn + Vector3(spread * (riders.size() % 3) - spread, 0.5, 0.0)})
	if riders.is_empty():
		return false
	EventBus.publish(&"missions.rode_home", {"mission": current.get("id", ""), "riders": riders})
	_broadcast(riders)
	_end_if_nobody_out()
	return true


func _end_if_nobody_out() -> void:
	if state != IN_MISSION or not _out.is_empty():
		return
	EventBus.publish(&"missions.ended", {"mission": current.get("id", "")})
	_runs += 1
	state = HOME
	current = {}
	offers = roll_offers(config, int(config["seed"]) + _runs)
	_broadcast()


## Server: a player who died out there wakes up at home (the player module respawns them at
## the spawn), so they are no longer out.
func _on_player_respawned(p: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var player := p.get("player") as Node
	if player != null and _out.erase(int(player.get_meta(&"peer_id", 1))):
		_end_if_nobody_out()


func _on_peer_left(peer: int) -> void:
	if multiplayer.is_server() and _out.erase(peer):
		_end_if_nobody_out()


## Server: tells everyone the offers, the mission and the run state; `riders` (peer ids) get
## the ride's fade.
func _broadcast(riders: Array = []) -> void:
	Net.server_broadcast(&"missions.changed", {"offers": offers, "current": current, "state": state, "riders": riders})


## Everywhere: takes the server's word for the mission state.
func _on_changed(p: Dictionary) -> void:
	offers = p.get("offers", offers)
	current = p.get("current", {})
	state = str(p.get("state", state))
	if current != _placed_for:
		_place_dropoff_car()
	if Net.has_local_player() and (p.get("riders", []) as Array).has(Net.local_peer_id()):
		EventBus.publish(&"missions.ride", {"seconds": float(config.get("ride_fade_seconds", 0.8))})


## Server: a friend who joins late sees the board and the mission as they are.
func _on_peer_joined(peer: int) -> void:
	if multiplayer.is_server():
		_sync.rpc_id(peer, offers, current, state)


@rpc("authority", "call_remote", "reliable")
func _sync(new_offers: Array, new_current: Dictionary, new_state: String) -> void:
	_on_changed({"offers": new_offers, "current": new_current, "state": new_state})


## Client only: the local player's prompt, board screen and ride fade.
func _on_player_spawned(p: Dictionary) -> void:
	if DisplayServer.get_name() == "headless" or not p.get("local", false):
		return
	var prompt := MissionPrompt.new()
	prompt.name = "MissionPrompt"
	prompt.missions = self
	prompt.player = p["player"] as Node3D
	add_child(prompt)
	var screen := MissionBoardScreen.new()
	screen.name = "MissionBoardScreen"
	screen.missions = self
	add_child(screen)
	var fade := RideFade.new()
	fade.name = "RideFade"
	add_child(fade)

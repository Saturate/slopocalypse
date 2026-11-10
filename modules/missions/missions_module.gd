extends Node
## Home base and the mission run. The start tunnel is home: a mission board on the wall
## offers a few missions, and the car parked inside rides everyone at home out to the chosen
## mission's drop-off point down the road; the car waiting there rides them back. The server
## owns the run (`home`, then `in_mission` until nobody is out any more) and tells everyone
## through `missions.*` topics.
##
## Each mission has a zone past the drop-off with buildings (MissionLayout) and is of one
## kind, a MissionType script named in data (Smash & Grab, Clean Sweep, ...). The kind lays
## out its content and decides when the job is done; riding home then pays everyone who rode
## home in tokens. This module only knows the run, the zone, the buildings, crates, pay and
## markers, plus hazards any mission can ask for in its data: buried mines around the
## buildings (`mines`) and tripwires across their doors (`tripwires`), with warning signs.

const CONFIG := "res://modules/missions/data/missions.json"
const REQUIRED := {
	"home_radius": TYPE_FLOAT, "reach": TYPE_FLOAT, "ride_fade_seconds": TYPE_FLOAT,
	"ride_home_reach": TYPE_FLOAT, "drop_spread": TYPE_FLOAT, "board": TYPE_DICTIONARY,
	"transport": TYPE_DICTIONARY, "dropoff_side": TYPE_FLOAT, "offered": TYPE_FLOAT,
	"seed": TYPE_FLOAT, "missions": TYPE_ARRAY, "zone": TYPE_DICTIONARY, "types": TYPE_DICTIONARY,
	"codenames": TYPE_DICTIONARY, "buildings": TYPE_DICTIONARY,
}
## How squarely you must face the board or a car to use it.
const FACING := 0.7
const MARKER_COLOUR := Color(1.0, 0.85, 0.5)
const MARKER_PIXEL_SIZE := 0.0008
## Markers are faint, and fade out over `MARKER_FADE` metres as you come within
## `MARKER_NEAR` of them: they point the way, the last bit you find yourself.
const MARKER_ALPHA := 0.55
const MARKER_NEAR := 10.0
const MARKER_FADE := 8.0
## Trees are cleared this far around a building's footprint.
const CLEARING_MARGIN := 4.0
const HOME := "home"
const IN_MISSION := "in_mission"

var config: Dictionary = {}
## Everywhere: the offered missions, the chosen one (or empty) and the run state, as the
## server last said.
var offers: Array = []
var current: Dictionary = {}
var state := HOME
## Everywhere: the zone's centre and its buildings as layout entries while a run is on.
var zone := Vector3.ZERO
var buildings: Array = []
## This instance's own player's tokens, as the server last said.
var my_tokens := 0
## Server: rolls for the run (strike spots, guard posts), seeded per run.
var rng := RandomNumberGenerator.new()

var _spawn := Vector3.ZERO
var _board: MissionBoard
var _transport: TransportCar
var _dropoff_car: TransportCar
## The mission the drop-off car stands for (the server sets `current` before it hears its
## own broadcast, so compare with this instead).
var _placed_for: Dictionary = {}
var _building_nodes: Array[MissionBuilding] = []
## Everywhere while a run is on: the kind of mission being run.
var _type: MissionType
## Server: peers out on the mission; how many runs have ended (rolls the next offers);
## crates the run put in the zone; peer -> tokens.
var _out: Dictionary = {}
var _runs := 0
var _crates: Array[Node3D] = []
var _mine_spawner := MultiplayerSpawner.new()
var _mines_spawned := 0
var _tokens: Dictionary = {}


func _ready() -> void:
	add_to_group(&"missions_api")
	var parsed: Variant = Data.load_json(CONFIG)
	if not parsed is Dictionary or not Data.require(CONFIG, parsed, REQUIRED):
		return
	config = parsed
	offers = roll_offers(config, int(config["seed"]))
	# Mines and wires are made by the server and replicated, so everyone sees the same ones.
	_mine_spawner.name = "MineSpawner"
	_mine_spawner.spawn_path = NodePath("..")
	_mine_spawner.spawn_function = _make_mine
	add_child(_mine_spawner)
	EventBus.subscribe(&"weapon.fired", _on_weapon_fired)
	EventBus.subscribe(&"explosion", _on_explosion)
	EventBus.subscribe(&"missions.building_broken", _on_building_broken)
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
	EventBus.unsubscribe(&"weapon.fired", _on_weapon_fired)
	EventBus.unsubscribe(&"explosion", _on_explosion)
	EventBus.unsubscribe(&"missions.building_broken", _on_building_broken)
	if Net.peer_joined.is_connected(_on_peer_joined):
		Net.peer_joined.disconnect(_on_peer_joined)
	if Net.peer_left.is_connected(_on_peer_left):
		Net.peer_left.disconnect(_on_peer_left)


## `offered` missions rolled from the config with `seed`: each picks a template (no repeats
## while there are enough), keeps the template's own fields, rolls its distance, payout and
## any other `[min, max]` count (guards), and gets a codename.
static func roll_offers(cfg: Dictionary, seed_value: int) -> Array:
	var rng_ := RandomNumberGenerator.new()
	rng_.seed = seed_value
	var templates: Array = (cfg.get("missions", []) as Array).duplicate()
	var names: Dictionary = cfg.get("codenames", {})
	var first: Array = names.get("first", ["Grey"])
	var second: Array = names.get("second", ["Fox"])
	var types: Dictionary = cfg.get("types", {})
	var out := []
	for i in int(cfg.get("offered", 3)):
		if templates.is_empty():
			templates = (cfg.get("missions", []) as Array).duplicate()
		if templates.is_empty():
			break
		var t: Dictionary = templates.pop_at(rng_.randi_range(0, templates.size() - 1))
		var offer := t.duplicate(true)
		var kind: Dictionary = types.get(str(t.get("type", "")), {})
		offer.merge(kind.get("defaults", {}), false)
		offer["type_name"] = str(kind.get("name", t.get("type", "")))
		offer["codename"] = "Operation %s %s" % [first[rng_.randi_range(0, first.size() - 1)], second[rng_.randi_range(0, second.size() - 1)]]
		offer["id"] = "%s:%s" % [t.get("type", ""), t.get("place", "")]
		for key: String in ["distance", "payout"]:
			var r: Array = t.get(key, [100.0, 200.0])
			offer[key] = snappedf(rng_.randf_range(float(r[0]), float(r[1])), 10.0)
		for key: String in ["guards", "patrols", "mines", "tripwires"]:
			if t.get(key) is Array:
				offer[key] = rng_.randi_range(int(t[key][0]), int(t[key][1]))
		out.append(offer)
	return out


## Where a mission drops the group off: beside the road `distance` metres out.
func dropoff_of(mission: Dictionary) -> Vector3:
	var at := _road_at(float(mission.get("distance", 0.0)))
	at.x += float(config.get("dropoff_side", 0.0))
	at.y = ground_y(at.x, at.z)
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
	var mine := disarmable(player)
	if mine != null:
		payload["handled"] = true
		mine.server_disarm()
		return
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
	_open_zone()
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
## `player`; if the job is done they are paid. The run ends once nobody is out any more.
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
	if _type != null and not bool(current.get("paid", false)) and _type.server_done(riders):
		_pay(riders)
	_broadcast(riders)
	_end_if_nobody_out()
	return true


func _pay(riders: Array) -> void:
	current["paid"] = true
	var pay := int(current.get("payout", 0))
	for peer: int in riders:
		server_set_tokens(peer, server_tokens_of(peer) + pay)
	EventBus.publish(&"missions.paid", {"mission": current.get("id", ""), "riders": riders, "tokens": pay})


func _end_if_nobody_out() -> void:
	if state != IN_MISSION or not _out.is_empty():
		return
	EventBus.publish(&"missions.ended", {"mission": current.get("id", ""), "paid": bool(current.get("paid", false))})
	_close_zone()
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


func _snapshot(riders: Array = []) -> Dictionary:
	return {"offers": offers, "current": current, "state": state, "riders": riders, "zone": zone, "buildings": buildings, "status": _type.status if _type != null else {}}


## Server: tells everyone the offers, the mission, the run state and the kind's status;
## `riders` (peer ids) get the ride's fade.
func _broadcast(riders: Array = []) -> void:
	Net.server_broadcast(&"missions.changed", _snapshot(riders))


## Server: the kind's status changed (a type calls this through `changed()`).
func type_changed() -> void:
	_broadcast()


## Everywhere: takes the server's word for the mission state.
func _on_changed(p: Dictionary) -> void:
	offers = p.get("offers", offers)
	current = p.get("current", {})
	state = str(p.get("state", state))
	zone = p.get("zone", zone)
	if p.has("buildings") and p["buildings"] != buildings:
		buildings = p["buildings"]
		_build_buildings()
	if _key(current) != _key(_placed_for):
		_place_dropoff_car()
	_sync_type()
	if _type != null and not multiplayer.is_server():
		_type.apply_status(p.get("status", {}))
	_update_markers()
	if Net.has_local_player() and (p.get("riders", []) as Array).has(Net.local_peer_id()):
		EventBus.publish(&"missions.ride", {"seconds": float(config.get("ride_fade_seconds", 0.8))})


## Which mission a dictionary is, ignoring run details such as `paid`.
static func _key(mission: Dictionary) -> String:
	return "%s@%s" % [mission.get("id", ""), mission.get("distance", 0)]


## Everywhere: makes (or drops) the kind of mission being run.
func _sync_type() -> void:
	var want := str(current.get("type", "")) if state == IN_MISSION else ""
	if _type != null and (want.is_empty() or str(_type.mission.get("type", "")) != want):
		_type.queue_free()
		_type = null
	if want.is_empty() or _type != null:
		return
	var kind: Dictionary = (config["types"] as Dictionary).get(want, {})
	var script := load(str(kind.get("script", ""))) as GDScript
	if script == null:
		Log.error(&"missions", "no script for mission type '%s'" % want)
		return
	_type = script.new()
	_type.name = "Type"
	_type.missions = self
	_type.mission = current
	add_child(_type)


## The HUD lines for a run under the mission's name (from its kind).
func hud_lines(player: Node3D) -> Array[String]:
	return _type.hud_lines(player) if _type != null else []


## Client: markers over the kind's targets and the drop-off car while a mission runs, seen
## through walls so they lead the way.
func _update_markers() -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var running := state == IN_MISSION
	var car_at := _dropoff_car.global_position + Vector3.UP * 3.4 if _dropoff_car != null else Vector3.ZERO
	_marker(&"CarMarker", car_at, "Car", running and _dropoff_car != null)
	var wanted: Array = _type.markers() if running and _type != null else []
	var i := 0
	while i < wanted.size() or get_node_or_null(NodePath("Marker%d" % i)) != null:
		var m: Dictionary = wanted[i] if i < wanted.size() else {}
		_marker(StringName("Marker%d" % i), m.get("at", Vector3.ZERO), str(m.get("text", "")), i < wanted.size())
		i += 1


func _marker(marker_name: StringName, at: Vector3, text: String, show: bool) -> void:
	var label := get_node_or_null(NodePath(marker_name)) as Label3D
	if label == null:
		if not show:
			return
		label = Label3D.new()
		label.name = marker_name
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = MARKER_PIXEL_SIZE
		label.font_size = 26
		label.outline_size = 6
		label.outline_modulate = Color(0, 0, 0, 0.5)
		label.modulate = Color(MARKER_COLOUR, MARKER_ALPHA)
		label.add_to_group(&"mission_markers")
		add_child(label)
	label.set_meta(&"caption", text.capitalize())
	label.global_position = at
	label.visible = show


## Client: each marker shows a small diamond and how far it is, fading out up close.
func _process(_delta: float) -> void:
	if DisplayServer.get_name() == "headless" or state != IN_MISSION:
		return
	var me := _local_player()
	if me == null:
		return
	for node: Node in get_tree().get_nodes_in_group(&"mission_markers"):
		var label := node as Label3D
		if not label.visible:
			continue
		var d := me.global_position.distance_to(label.global_position)
		label.text = "◆\n%s %d m" % [label.get_meta(&"caption", ""), int(d)]
		label.modulate.a = MARKER_ALPHA * clampf((d - MARKER_NEAR) / MARKER_FADE, 0.0, 1.0)


func _local_player() -> Node3D:
	if not Net.has_local_player():
		return null
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if int(node.get_meta(&"peer_id", 0)) == Net.local_peer_id():
			return node as Node3D
	return null


## Server: a friend who joins late sees the board and the mission as they are.
func _on_peer_joined(peer: int) -> void:
	if multiplayer.is_server():
		_sync.rpc_id(peer, _snapshot())


@rpc("authority", "call_remote", "reliable")
func _sync(p: Dictionary) -> void:
	_on_changed(p)


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


## Server: lays out the zone past the drop-off with its buildings, then lets the mission's
## kind put its content in.
func _open_zone() -> void:
	var z: Dictionary = config["zone"]
	var along := float(current.get("distance", 0.0)) + float(z.get("beyond_dropoff", 70.0))
	zone = _road_at(along)
	zone.y = ground_y(zone.x, zone.z)
	rng.seed = int(config["seed"]) * 31 + _runs
	# A mission can override the layout (a lone cabin: one building, far from the road).
	var layout: Dictionary = (config["buildings"] as Dictionary).duplicate()
	layout.merge(current.get("buildings", {}), true)
	buildings = MissionLayout.buildings(layout, int(config["seed"]) * 7919 + _runs, _road_at, along)
	for entry: Dictionary in buildings:
		var at: Vector3 = entry["position"]
		# A little sunk, so the slab never floats.
		at.y = ground_y(at.x, at.z) - 0.05
		entry["position"] = at
	_build_buildings()
	_sync_type()
	if _type != null:
		_type.server_open()
	_place_hazards()


## Server: the mission's mines around its buildings and tripwires across their doors, plus
## a few warning signs at the edge of the minefield.
func _place_hazards() -> void:
	var count := int(current.get("mines", 0))
	var wires := int(current.get("tripwires", 0))
	var h: Dictionary = config.get("hazards", {})
	var ring: Array = h.get("mine_ring", [3.0, 14.0])
	var keep_clear := float(h.get("door_clear", 2.0))
	for i in count:
		var centre: Vector3 = zone
		var radius := 4.0
		if not buildings.is_empty():
			var b: Dictionary = buildings[rng.randi_range(0, buildings.size() - 1)]
			centre = b["position"]
			radius = float(b.get("radius", 4.0))
		var a := rng.randf() * TAU
		var r := radius + rng.randf_range(float(ring[0]), float(ring[1]))
		var at := centre + Vector3(cos(a) * r, 0.0, sin(a) * r)
		# Not right on a doorstep: the wire is for that.
		var on_step := _building_nodes.any(func(n: MissionBuilding) -> bool: return at.distance_to(n.global_transform * Vector3(0, 0, -float(n.spec["depth"]) / 2.0 - 1.0)) < keep_clear)
		if on_step:
			continue
		at.y = ground_y(at.x, at.z)
		server_spawn_hazard("mine", at, Vector3.ZERO)
	for i in mini(wires, _building_nodes.size()):
		var n := _building_nodes[i]
		var d := float(n.spec["depth"])
		var a := n.global_transform * Vector3(-MissionBuilding.DOOR_WIDTH / 2.0, MissionBuilding.SLAB + 0.15, -d / 2.0 - 0.05)
		var b := n.global_transform * Vector3(MissionBuilding.DOOR_WIDTH / 2.0, MissionBuilding.SLAB + 0.15, -d / 2.0 - 0.05)
		server_spawn_hazard("wire", a, b)
	if count > 0:
		for i in int(h.get("signs", 2)):
			var a := rng.randf() * TAU
			var at := zone + Vector3(cos(a), 0.0, sin(a)) * float(h.get("sign_distance", 30.0))
			at.y = ground_y(at.x, at.z)
			server_spawn_hazard("sign", at, Vector3.ZERO)


## Server: one mine ("mine"), tripwire from `at` to `end` ("wire") or warning sign ("sign").
func server_spawn_hazard(kind: String, at: Vector3, end: Vector3) -> Node3D:
	_mines_spawned += 1
	return _mine_spawner.spawn({"index": _mines_spawned, "kind": kind, "position": at, "end": end})


func _make_mine(data: Variant) -> Node:
	var info: Dictionary = data
	if str(info["kind"]) == "sign":
		var sign := MineSign.new()
		sign.name = "Sign%d" % int(info["index"])
		sign.position = info["position"]
		sign.rotation.y = float(int(info["index"]) * 71 % 360) * PI / 180.0
		return sign
	var mine := Mine.new()
	mine.name = "Mine%d" % int(info["index"])
	mine.kind = str(info["kind"])
	mine.position = info["position"]
	mine.wire_end = info.get("end", Vector3.ZERO)
	mine.cfg = config.get("hazards", {})
	return mine


## Server: a blast near the zone's buildings breaks the wall and roof segments it wears
## out, for everyone.
func _on_explosion(p: Dictionary) -> void:
	if not multiplayer.is_server() or not p.has("position"):
		return
	var cfg: Dictionary = config["buildings"]
	var at: Vector3 = p["position"]
	var radius := float(p.get("radius", 2.0))
	for i in _building_nodes.size():
		var b := _building_nodes[i]
		if b.global_position.distance_to(at) > radius * float(cfg.get("blast_reach", 1.6)) + 8.0:
			continue
		var broke := b.server_blast(at, radius, float(cfg.get("blast_damage", 140.0)), float(cfg.get("blast_reach", 1.6)))
		if not broke.is_empty():
			Net.server_broadcast(&"missions.building_broken", {"index": i, "segments": broke})


## Everywhere: segments of a building broke; the layout entry remembers it for late joiners.
func _on_building_broken(p: Dictionary) -> void:
	var i := int(p.get("index", -1))
	if i < 0 or i >= _building_nodes.size() or i >= buildings.size():
		return
	var segs: Array = p.get("segments", [])
	var entry: Dictionary = buildings[i]
	var broken: Array = entry.get("broken", [])
	for s: Variant in segs:
		if not broken.has(int(s)):
			broken.append(int(s))
	entry["broken"] = broken
	_building_nodes[i].break_segments(segs)


## Server: a bullet that hits close to a mine sets it off.
func _on_weapon_fired(p: Dictionary) -> void:
	if not multiplayer.is_server() or not p.has("to"):
		return
	var hit: Vector3 = p["to"]
	for node: Node in get_tree().get_nodes_in_group(&"mines"):
		var mine := node as Mine
		if mine != null and mine.is_armed() and mine.kind == "mine" and mine.global_position.distance_to(hit) < float((config.get("hazards", {}) as Dictionary).get("shot_radius", 0.4)):
			mine.server_detonate()


## The armed mine or wire `player` could disarm now (crouched, close), or null.
func disarmable(player: Node3D) -> Mine:
	if not (player as PlayerController).intent().crouch:
		return null
	var reach := float((config.get("hazards", {}) as Dictionary).get("disarm_range", 1.4))
	for node: Node in get_tree().get_nodes_in_group(&"mines"):
		var mine := node as Mine
		if mine != null and mine.is_armed() and mine.global_position.distance_to(player.global_position) < reach:
			return mine
	return null


## Server: the run is over: the kind cleans up, then the crates and buildings go.
func _close_zone() -> void:
	if _type != null:
		_type.server_close()
	var inventory := get_tree().get_first_node_in_group(&"inventory_api")
	for crate in _crates:
		if inventory != null and is_instance_valid(crate):
			inventory.call(&"server_remove_container", crate)
	_crates.clear()
	for node: Node in get_tree().get_nodes_in_group(&"mines") + get_tree().get_nodes_in_group(&"mine_signs"):
		node.queue_free()
	buildings = []
	_build_buildings()


func server_tokens_of(peer: int) -> int:
	return int(_tokens.get(peer, 0))


## Server: sets `peer`'s tokens (pay, the trader, a loaded save) and tells them.
func server_set_tokens(peer: int, tokens: int) -> void:
	_tokens[peer] = maxi(tokens, 0)
	if peer == multiplayer.get_unique_id():
		my_tokens = _tokens[peer]
	elif multiplayer.get_peers().has(peer):
		_receive_tokens.rpc_id(peer, int(_tokens[peer]))


@rpc("authority", "call_remote", "reliable")
func _receive_tokens(tokens: int) -> void:
	my_tokens = tokens


func _physics_process(delta: float) -> void:
	var prof := Prof.start()
	_physics_tick(delta)
	Prof.stop(&"missions/module:physics", prof)


func _physics_tick(delta: float) -> void:
	if state != IN_MISSION or _type == null:
		return
	_type.client_tick(delta)
	if multiplayer.is_server():
		_type.server_tick(delta)


# --- For mission types -------------------------------------------------------------------

func building_nodes() -> Array[MissionBuilding]:
	return _building_nodes


## Server: a crate at `at` holding exactly `items`, gone when the run ends.
func spawn_crate(at: Vector3, items: Array) -> Node3D:
	var inventory := get_tree().get_first_node_in_group(&"inventory_api")
	if inventory == null:
		return null
	var crate: Node3D = inventory.call(&"server_spawn_mission_crate", at, items)
	if crate != null:
		_crates.append(crate)
	return crate


## Server: a crate of rolled loot in every building but those at `skip` (indices).
func fill_buildings_with_loot(skip: Array) -> void:
	var inventory := get_tree().get_first_node_in_group(&"inventory_api")
	if inventory == null:
		return
	for i in _building_nodes.size():
		if not skip.has(i):
			spawn_crate(_building_nodes[i].inside(0.8, 0.5), inventory.call(&"roll_crate_loot"))


## Server: the riders (living, out on this run) inside the zone.
func riders_in_zone() -> Array[Node3D]:
	var radius := float((config["zone"] as Dictionary).get("radius", 45.0))
	var out: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var p := node as Node3D
		if p != null and _out.has(int(p.get_meta(&"peer_id", 1))) and not p.get_meta(&"dead", false) and Vector2(p.global_position.x - zone.x, p.global_position.z - zone.z).length() < radius:
			out.append(p)
	return out


## Server: a random spot on the ground in the zone, within `share` of its radius.
func random_spot(share: float) -> Vector3:
	var radius := float((config["zone"] as Dictionary).get("radius", 45.0)) * share
	var a := rng.randf() * TAU
	var r := sqrt(rng.randf()) * radius
	var at := zone + Vector3(cos(a) * r, 0.0, sin(a) * r)
	at.y = ground_y(at.x, at.z)
	return at


## The untouched ground's height (0 without a world, as in tests).
func ground_y(x: float, z: float) -> float:
	var ground := get_tree().get_first_node_in_group(&"ground")
	if ground != null and ground.has_method(&"ground_height"):
		return float(ground.call(&"ground_height", x, z))
	return 0.0


## A point on the road `metres` out (straight down -z without a world, as in tests).
func _road_at(metres: float) -> Vector3:
	var ground := get_tree().get_first_node_in_group(&"ground")
	if ground != null and ground.has_method(&"road_point"):
		return ground.call(&"road_point", metres)
	return Vector3(0.0, 0.0, -metres)


## Everywhere: (re)builds the zone's buildings from `buildings`, with the trees around
## them cleared.
func _build_buildings() -> void:
	for node in _building_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_building_nodes.clear()
	if not is_inside_tree():
		return
	var scenery := get_tree().get_first_node_in_group(&"scenery")
	if scenery != null:
		var circles := []
		for entry: Dictionary in buildings:
			circles.append({"at": entry["position"], "radius": float(entry.get("radius", 4.0)) + CLEARING_MARGIN})
		scenery.call(&"set_clearings", circles)
	for i in buildings.size():
		var entry: Dictionary = buildings[i]
		var b := MissionBuilding.new()
		b.name = "Building%d" % i
		b.spec = entry
		b.segment_size = float((config["buildings"] as Dictionary).get("segment", 1.2))
		b.segment_hp = float((config["buildings"] as Dictionary).get("segment_hp", 100.0))
		add_child(b)
		b.global_position = entry["position"]
		b.rotation.y = float(entry["yaw"])
		_building_nodes.append(b)

extends Node
## The city (#333, #220, part of #331): a European city of perimeter blocks beside the road
## (CitySite), on levelled ground cleared of trees, that you can walk into and fight through.
## Placed the same on the server and every client from data and the road, so nothing about
## it is sent. Its street lamps are the lights module's: once the city stands, it publishes
## where they go on `city.lamp_spots` ({spots: Array[Transform3D]}), so either works with
## the other switched off.

const CONFIG := "res://modules/city/data/city.json"
const REQUIRED := {
	"seed": TYPE_FLOAT, "at": TYPE_FLOAT, "side": TYPE_FLOAT, "size": TYPE_FLOAT, "blocks": TYPE_FLOAT,
	"street_width": TYPE_FLOAT, "avenue_width": TYPE_FLOAT, "street_jitter": TYPE_FLOAT, "pavement": TYPE_FLOAT,
	"passage_width": TYPE_FLOAT, "gateway_height": TYPE_FLOAT, "building_depth": TYPE_FLOAT, "floors_edge": TYPE_FLOAT,
	"floors_middle": TYPE_FLOAT, "style": TYPE_STRING, "asphalt": TYPE_ARRAY, "kerb_width": TYPE_FLOAT, "tile_size": TYPE_FLOAT,
	"crossing_width": TYPE_FLOAT, "crossing_setback": TYPE_FLOAT, "zebra_stripe": TYPE_FLOAT, "lamp_spacing": TYPE_FLOAT,
	"lamp_inset": TYPE_FLOAT, "tree_spacing": TYPE_FLOAT, "tree_inset": TYPE_FLOAT, "tree_street_width": TYPE_FLOAT,
	"tree_height": TYPE_FLOAT, "tree_crown": TYPE_FLOAT, "tree_trunk": TYPE_FLOAT, "door_clear": TYPE_FLOAT,
	"spot_nudge": TYPE_FLOAT, "pad_blend": TYPE_FLOAT, "builds_per_frame": TYPE_FLOAT,
}
## Clearing circles over the footprint are this far apart.
const CLEARING_STEP := 20.0
## Metres between road samples when keeping the city off the road: finer than the road
## bends, so no stretch of it slips between two samples into the footprint.
const ROAD_CHECK_STEP := 2.0
## `--start=city`: the server puts every player down in the city's streets instead of at
## the spawn (and back there after dying); `--bot=city` walks its avenues (CityBot). Both
## for `tools/bench.ts solo-city` and for playtesting the city without the drive out.
const START_ARG := "--start=city"
const BOT_ARG := "--bot=" + CityBot.BEHAVIOUR

var config: Dictionary = {}
var site: CitySite
## Server: the city's guards.
var garrison: CityGarrison
## Server: the people living in it.
var civilians: CityCivilians
## Players (server) and bots (local) that arrived before the city stood, for when it does.
var _waiting_players: Array[Node3D] = []
var _waiting_bots: Array[CityBot] = []


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not (data is Dictionary and Data.require(CONFIG, data, REQUIRED)):
		return
	config = data
	EventBus.subscribe(&"world.ready", _on_world_ready)
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	EventBus.subscribe(&"player.respawned", _on_player_respawned)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)
	EventBus.unsubscribe(&"player.respawned", _on_player_respawned)


func _on_player_spawned(p: Dictionary) -> void:
	var player := p.get("player") as PlayerController
	if player == null:
		return
	var args := Net.session_args()
	if bool(p.get("local", false)) and args.has(BOT_ARG):
		var bot := CityBot.new()
		bot.name = "CityBot"
		bot.player = player
		bot.site = site
		player.add_child(bot)
		if site == null:
			_waiting_bots.append(bot)
	if multiplayer.is_server() and args.has(START_ARG):
		_server_put_in_city(player)


func _on_player_respawned(p: Dictionary) -> void:
	var player := p.get("player") as PlayerController
	if player != null and multiplayer.is_server() and Net.session_args().has(START_ARG):
		_server_put_in_city(player)


## Server: down in the street where the city walk starts, once the city stands. After the
## spawn settles, so other modules equip and place the player first.
func _server_put_in_city(player: Node3D) -> void:
	if site == null:
		_waiting_players.append(player)
		return
	(func() -> void:
		if is_instance_valid(player) and site != null:
			EventBus.publish(&"player.move_requested", {"player": player, "position": CityBot.start_spot(site)})
	).call_deferred()


func _on_world_ready(_p: Dictionary) -> void:
	if site != null:
		return
	var ground := get_tree().get_first_node_in_group(&"ground")
	if ground == null or not ground.has_method(&"road_point"):
		return
	place(spot(ground, config))
	var size := float(config["size"])
	if ground.has_method(&"set_pads_for"):
		ground.call(&"set_pads_for", &"city", [{"at": site.global_position, "half": Vector2(size / 2.0, size / 2.0), "yaw": site.global_rotation.y, "blend": float(config["pad_blend"])}])
	var scenery := get_tree().get_first_node_in_group(&"scenery")
	if scenery != null and scenery.has_method(&"set_clearings_for"):
		scenery.call(&"set_clearings_for", &"city", clearings(site.global_transform, size))
	publish_lamps()


## Everywhere: where the city's street lamps go, for whoever puts lamps up.
func publish_lamps() -> void:
	if site != null:
		EventBus.publish(&"city.lamp_spots", {"spots": site.lamp_spots()})


## Where the city stands: beside the road `at` metres out, its near edge `side` metres from
## the road's middle, squared to the road there and level at the ground's middle height.
static func spot(ground: Node, cfg: Dictionary) -> Transform3D:
	var m := float(cfg["at"])
	var centre: Vector3 = ground.call(&"road_point", m)
	var along: Vector3 = (ground.call(&"road_point", m + 1.0) as Vector3) - centre
	along.y = 0.0
	along = along.normalized() if along.length() > 0.001 else Vector3.FORWARD
	var right := along.cross(Vector3.UP)
	var side := float(cfg["side"])
	var size := float(cfg["size"])
	var away := right * signf(side) if side != 0.0 else right
	var at := centre + away * (absf(side) + size / 2.0)
	# -z toward the road.
	var basis := Basis.looking_at(-away)
	# Squared to the road at one point, the city would let a bend further along run into it:
	# moved out until the whole stretch beside it keeps `side` off its near edge.
	var reach := size / 2.0 + absf(side)
	var step := ROAD_CHECK_STEP
	var metres := m - reach * 2.0
	var push := 0.0
	while metres <= m + reach * 2.0:
		var local := basis.inverse() * ((ground.call(&"road_point", metres) as Vector3) - at)
		# Past a corner, `side` is measured from the corner, not straight out.
		var past := maxf(absf(local.x) - size / 2.0, 0.0)
		if past < absf(side):
			push = maxf(push, local.z + size / 2.0 + sqrt(side * side - past * past))
		metres += step
	at += away * push
	var heights: Array[float] = []
	for c: Vector3 in [Vector3.ZERO, Vector3(size / 2.0, 0, size / 2.0), Vector3(-size / 2.0, 0, size / 2.0), Vector3(size / 2.0, 0, -size / 2.0), Vector3(-size / 2.0, 0, -size / 2.0)]:
		var p := at + basis * c
		heights.append(float(ground.call(&"ground_height", p.x, p.z)))
	heights.sort()
	at.y = heights[heights.size() / 2]
	return Transform3D(basis, at)


## Circles covering the square footprint, so nothing grows in the city.
static func clearings(where: Transform3D, size: float) -> Array:
	var out: Array = []
	var steps := ceili(size / CLEARING_STEP)
	for i in steps + 1:
		for j in steps + 1:
			var local := Vector3(-size / 2.0 + i * size / steps, 0.0, -size / 2.0 + j * size / steps)
			out.append({"at": where * local, "radius": CLEARING_STEP * 0.75})
	return out


## Everywhere: the city at `where`.
func place(where: Transform3D) -> void:
	site = CitySite.new()
	site.name = "City"
	site.config = config
	site.transform = where
	add_child(site)
	if multiplayer.is_server():
		garrison = CityGarrison.new()
		garrison.name = "Garrison"
		garrison.config = config.get("guards", {})
		garrison.site = site
		add_child(garrison)
		civilians = CityCivilians.new()
		civilians.name = "Civilians"
		civilians.config = config.get("civilians", {})
		civilians.site = site
		add_child(civilians)
	for bot in _waiting_bots:
		if is_instance_valid(bot):
			bot.site = site
	_waiting_bots.clear()
	for player in _waiting_players:
		if is_instance_valid(player):
			_server_put_in_city(player)
	_waiting_players.clear()

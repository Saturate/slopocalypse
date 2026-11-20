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
	"approach_blend": TYPE_FLOAT, "approach_max_grade": TYPE_FLOAT,
}
## Clearing circles over the footprint are this far apart.
const CLEARING_STEP := 20.0
## Metres between road samples when keeping the city off the road: finer than the road
## bends, so no stretch of it slips between two samples into the footprint.
const ROAD_CHECK_STEP := 2.0
## Metres the street in starts under the road's asphalt (drawn a few cm higher), so its end
## is hidden there instead of standing on the voxel ground, which draws up to a voxel low.
const APPROACH_TUCK := 1.0
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
	# On a generated map the city has its place already: its footprint, level and road side
	# (#472). The map's road and earthworks bring the road in and level the ground.
	var on_map: Dictionary = ground.call(&"map_city") if ground.has_method(&"map_city") else {}
	if not on_map.is_empty():
		place(Transform3D(Basis.looking_at(on_map["toward"]), on_map["centre"]))
		var scenery_on_map := get_tree().get_first_node_in_group(&"scenery")
		if scenery_on_map != null and scenery_on_map.has_method(&"set_clearings_for"):
			scenery_on_map.call(&"set_clearings_for", &"city", clearings(site.global_transform, float(config["size"])))
		publish_lamps()
		return
	place(spot(ground, config))
	var size := float(config["size"])
	var lead := approach(ground, site.global_transform, site.plan, config)
	site.lead_in(lead)
	var pads := [{"at": site.global_position, "half": Vector2(size / 2.0, size / 2.0), "yaw": site.global_rotation.y, "blend": float(config["pad_blend"])}]
	var circles := clearings(site.global_transform, size)
	if not lead.is_empty():
		var from := float(lead["from"])
		var to := float(lead["to"])
		var half := Vector2(float(lead["width"]) / 2.0 + float(config["pavement"]), (to - from) / 2.0)
		pads.append({"at": site.global_transform * Vector3(float(lead["x"]), 0.0, (from + to) / 2.0), "half": half, "yaw": site.global_rotation.y,
			"blend": float(config["approach_blend"]), "from_ground": true})
		var z := from
		while z < to:
			circles.append({"at": site.global_transform * Vector3(float(lead["x"]), 0.0, z), "radius": half.x + float(config["approach_blend"])})
			z += CLEARING_STEP / 2.0
	if ground.has_method(&"set_pads_for"):
		ground.call(&"set_pads_for", &"city", pads)
	var scenery := get_tree().get_first_node_in_group(&"scenery")
	if scenery != null and scenery.has_method(&"set_clearings_for"):
		scenery.call(&"set_clearings_for", &"city", circles)
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
	# No steeper than `approach_max_grade` up the street in from the road: the city sits
	# within that of the road's height over the ramp between the road's band and its edge.
	var band := 0.0
	if ground.has_method(&"road_share_at"):
		while band < absf(side) + push:
			var p := centre + away * band
			if float(ground.call(&"road_share_at", p.x, p.z)) >= 1.0:
				break
			band += ROAD_CHECK_STEP / 8.0
	var ramp := maxf(absf(side) + push - band, 1.0)
	var grade := float(cfg.get("approach_max_grade", 1.0)) * ramp
	at.y = clampf(at.y, centre.y - grade, centre.y + grade)
	return Transform3D(basis, at)


## The street in from the road, in the city's own metres (see `CitySite.lead_in`): straight
## out from the ring street along the inner street nearest the road to the road's middle,
## at the road's height. Empty if the road never crosses that line beside the city.
static func approach(ground: Node, where: Transform3D, plan: Dictionary, cfg: Dictionary) -> Dictionary:
	var size := float(cfg["size"])
	var m := float(cfg["at"])
	var inverse := where.affine_inverse()
	var aim := (inverse * (ground.call(&"road_point", m) as Vector3)).x
	var lines: Array = plan["lines"][0]
	var widths: Array = plan["widths"]
	var x := 0.0
	var width := float(cfg["street_width"])
	var best := INF
	for i in range(1, lines.size() - 1):
		var centre := float(lines[i]) + float(widths[i]) / 2.0
		if absf(centre - aim) < best:
			best = absf(centre - aim)
			x = centre
			width = float(widths[i])
	# Where the road crosses that line: the nearest of its points, finely sampled.
	var hit := Vector3.ZERO
	best = INF
	var metres := m - size
	while metres <= m + size:
		var local := inverse * (ground.call(&"road_point", metres) as Vector3)
		if absf(local.x - x) < best and local.z < -size / 2.0:
			best = absf(local.x - x)
			hit = local
		metres += ROAD_CHECK_STEP / 4.0
	if best > ROAD_CHECK_STEP:
		return {}
	# The road keeps its own level across its band, wider along this line where the road
	# crosses it at an angle: the street runs flat at the road's height to the band's end and
	# only then slopes to the city.
	# The drawn street starts at the road's edge along this line (`edge`), not over the road,
	# whose asphalt curves under any straight piece laid across it.
	var from := hit.z
	var edge := hit.z
	if ground.has_method(&"road_share_at"):
		while from < -size / 2.0:
			var p := where * Vector3(x, 0.0, from)
			var share := float(ground.call(&"road_share_at", p.x, p.z))
			if share <= 0.0:
				edge = from
			if share >= 1.0:
				break
			from += ROAD_CHECK_STEP / 8.0
	if -size / 2.0 - from < 1.0:
		return {}
	edge = maxf(edge - APPROACH_TUCK, hit.z)
	# The road climbs as it goes, and crosses this line at an angle: across its band the ground
	# is the road's height where each point is, so both ends of the flat stretch take theirs.
	var at_edge := where * Vector3(x, 0.0, edge)
	var at_from := where * Vector3(x, 0.0, from)
	var level := where.origin.y
	return {"x": x, "width": width, "road": hit.z, "edge": edge, "from": from, "to": -size / 2.0,
		"edge_drop": float(ground.call(&"ground_height", at_edge.x, at_edge.z)) - level,
		"drop": float(ground.call(&"ground_height", at_from.x, at_from.z)) - level}


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

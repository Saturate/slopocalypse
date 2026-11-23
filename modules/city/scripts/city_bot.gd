class_name CityBot
extends Node
## `--bot=city`: walks this instance's player round and round the ring of avenues about the
## city's middle block, looking where it goes, through the same intent path a person uses
## (on a client it sends the intent to the server). A fixed, repeatable load for
## `tools/bench.ts solo-city`: the city's buildings, lamps, trees and guards from the street.

const BEHAVIOUR := "city"
## A waypoint counts as reached this close (metres, on the ground).
const REACH := 1.5

var player: PlayerController
var site: CitySite

var _ticks := 0
var _route: Array[Vector2] = []
var _next := 0


## The ring round the middle block, in the city's own space: the centre lines of the two
## inner streets on each axis (the outer ring when the city has too few blocks for inner
## ones), corner by corner, so a walk visits every side of the square.
static func route(plan: Dictionary) -> Array[Vector2]:
	var lines: Array = plan.get("lines", [[], []])
	var widths: Array = plan.get("widths", [])
	var n := (lines[0] as Array).size() - 1
	if n < 1 or widths.size() < n + 1:
		return []
	var a := 1 if n >= 3 else 0
	var b := n - 1 if n >= 3 else n
	var centre := func(axis: int, i: int) -> float:
		return float(lines[axis][i]) + float(widths[i]) / 2.0
	var xa: float = centre.call(0, a)
	var xb: float = centre.call(0, b)
	var za: float = centre.call(1, a)
	var zb: float = centre.call(1, b)
	return [Vector2(xa, za), Vector2(xa, zb), Vector2(xb, zb), Vector2(xb, za)]


## Where a walk starts, in world space: the first corner of the route, at street level.
static func start_spot(site_node: CitySite) -> Vector3:
	var corners := route(site_node.plan)
	if corners.is_empty():
		return site_node.global_position
	return site_node.global_transform * Vector3(corners[0].x, CitySite.KERB + 0.5, corners[0].y)


func _physics_process(_delta: float) -> void:
	var prof := Prof.start()
	_physics_tick()
	Prof.stop(&"city/bot:physics", prof)


func _physics_tick() -> void:
	if player == null or site == null or not is_instance_valid(site):
		return
	if _route.is_empty():
		_route = route(site.plan)
		if _route.is_empty():
			return
	_ticks += 1
	# The keyboard and mouse reader sends its own intent every tick (nobody at the mouse)
	# and would race this one.
	var input := player.get_node_or_null("Input")
	if input != null and input.is_physics_processing():
		input.set_physics_process(false)
	var target := site.global_transform * Vector3(_route[_next].x, 0.0, _route[_next].y)
	var to := target - player.global_position
	to.y = 0.0
	if to.length() < REACH:
		_next = (_next + 1) % _route.size()
		return
	# A Godot node faces -Z, so this yaw points the player along `to`.
	var yaw := atan2(-to.x, -to.z)
	var intent := player.intent()
	if multiplayer.is_server():
		intent.move = Vector2(0.0, 1.0)
		player.rotation.y = yaw
	else:
		intent.submit.rpc_id(1, Vector2(0.0, 1.0), yaw, 0.0, false, false, false, false)

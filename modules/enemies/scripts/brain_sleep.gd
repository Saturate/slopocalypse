class_name BrainSleep
extends Node
## Server: soldiers and civilians far from every player sleep. A sleeping one's body and brain
## don't step at all (no walking, looking or shooting); it stands where it was. It wakes
## once a player comes within `distance`, and falls asleep again only past `distance +
## margin`, so it doesn't flicker at the edge. With nobody connected, everyone sleeps.
##
## `distance` stays past what clients are sent (data/net.json's relevance distance and
## margin), so nobody a player can see is ever asleep. One with something on its mind (a
## soldier with a target or under fire, an alarmed civilian) stays awake wherever it is, and
## a sleeper that hears a shot, a blast or a squad mate's call wakes at once (`wake`), so a
## fight started far from players (soldiers of two factions) plays out.

const CONFIG := "res://modules/enemies/data/enemies.json"

var distance := 360.0
var margin := 40.0
var every := 0.5
var _since := 0.0


func _ready() -> void:
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary:
		return
	var cfg: Dictionary = (data as Dictionary).get("sleep", {})
	if Data.require(CONFIG, cfg, {"distance": TYPE_FLOAT, "margin": TYPE_FLOAT, "check_seconds": TYPE_FLOAT}):
		distance = float(cfg["distance"])
		margin = float(cfg["margin"])
		every = float(cfg["check_seconds"])


## Whether one `nearest` metres from the closest player (INF with nobody there) sleeps:
## past `reach + margin`, or, if it already does, past `reach`.
static func sleeps(was: bool, nearest: float, reach: float, margin_m: float) -> bool:
	return nearest > reach + (0.0 if was else margin_m)


static func is_asleep(body: Node) -> bool:
	var brain := body.get_node_or_null("Brain")
	return brain != null and not brain.is_physics_processing()


## Stops `body` and its brain where they stand. Its intent is let go first, so its gun does
## not keep firing a burst it was in the middle of.
static func put_to_sleep(body: PlayerController) -> void:
	var brain := body.get_node_or_null("Brain")
	if brain == null or not brain.is_physics_processing():
		return
	var intent := body.intent()
	intent.move = Vector2.ZERO
	intent.fire = false
	intent.sprint = false
	brain.set_physics_process(false)
	body.set_physics_process(false)
	body.set_process(false)


## Starts `body` and its brain again (not a dead one: its body stays stopped).
static func wake(body: PlayerController) -> void:
	var brain := body.get_node_or_null("Brain")
	if brain == null or brain.is_physics_processing() or body.get_meta(&"dead", false):
		return
	brain.set_physics_process(true)
	body.set_physics_process(true)
	body.set_process(true)


func _physics_process(delta: float) -> void:
	_since += delta
	if _since < every:
		return
	_since = 0.0
	var prof := Prof.start()
	update()
	Prof.stop(&"enemies/brain_sleep", prof)


## Puts far ones to sleep and wakes near (or busy) ones.
func update() -> void:
	var spots: Array[Vector3] = []
	for p: Node in get_tree().get_nodes_in_group(&"players"):
		if p is Node3D:
			spots.append((p as Node3D).global_position)
	for group: StringName in [&"enemies", &"civilians"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as PlayerController
			if body == null or body.get_meta(&"dead", false):
				continue
			var brain := body.get_node_or_null("Brain")
			if brain == null:
				continue
			var nearest := INF
			for at in spots:
				nearest = minf(nearest, at.distance_to(body.global_position))
			var busy := brain.has_method(&"busy") and bool(brain.call(&"busy"))
			if not busy and sleeps(not brain.is_physics_processing(), nearest, distance, margin):
				put_to_sleep(body)
			else:
				wake(body)

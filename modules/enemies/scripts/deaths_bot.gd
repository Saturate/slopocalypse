class_name DeathsBot
extends Node
## `--bench=deaths` (server): a fixed, repeatable load for `tools/bench.ts solo-deaths`. Round
## after round it puts a squad on the ground in front of the first player, gives them a
## moment, then kills them one at a time, so the perf log catches what a soldier appearing
## and a soldier dying cost on every client that sees it. The player cannot be hurt meanwhile.

const FLAG := "--bench=deaths"
## Seconds before the first round: loading and the bench's warm-up are not what this measures.
const FIRST_ROUND := 15.0
## How far ahead of the player the squad stands: close enough to fill the view.
const AHEAD := 10.0
const SQUAD := 3
## Seconds from a squad landing to the first kill, then between kills.
const ALIVE_FOR := 3.0
const KILL_GAP := 1.0
## Seconds after the last kill before the next round.
const ROUND_GAP := 3.0

var enemies: Node

var _wait := FIRST_ROUND
var _alive: Array[Node] = []


func _physics_process(delta: float) -> void:
	var prof := Prof.start()
	_physics_tick(delta)
	Prof.stop(&"enemies/deaths_bot:physics", prof)


func _physics_tick(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	var player := _player()
	if player == null:
		return
	var health := player.get_node_or_null("Health") as HealthComponent
	if health != null:
		health.invulnerable = true
	# Untyped: a freed soldier cannot be passed as a Node.
	_alive = _alive.filter(func(n: Variant) -> bool: return is_instance_valid(n) and not (n as Node).get_meta(&"dead", false))
	if _alive.is_empty():
		var ahead := -player.global_transform.basis.z
		ahead.y = 0.0
		_alive = enemies.call(&"server_spawn_squad", SQUAD, player.global_position + ahead.normalized() * AHEAD)
		_wait = ALIVE_FOR
		return
	var victim := _alive.pop_front() as Node
	var victim_health := victim.get_node_or_null("Health") as HealthComponent
	if victim_health != null:
		# No killer: credit or standing for the player would change how squads treat them
		# from run to run.
		victim_health.server_apply_damage(victim_health.max_health * 10.0)
	_wait = KILL_GAP if not _alive.is_empty() else ROUND_GAP


func _player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if int(node.get_meta(&"peer_id", 0)) > 0:
			return node as Node3D
	return null

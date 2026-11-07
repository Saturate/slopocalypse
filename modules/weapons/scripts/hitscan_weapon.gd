class_name HitscanWeapon
extends Node3D
## A carried hitscan gun's logic, at the holder's camera so shots follow the aim. It has
## no mesh: the one visible rifle is in the body's hands. Reads the holder's PlayerIntent;
## the server decides every hit.
## Fire rules (rate, magazine, reload, spread) run in Rust (`WeaponRules`).

const CONFIG := "res://modules/weapons/data/weapons.json"
const REQUIRED := {
	"damage": TYPE_FLOAT,
	"rounds_per_minute": TYPE_FLOAT,
	"magazine": TYPE_FLOAT,
	"reload_seconds": TYPE_FLOAT,
	"spread_degrees": TYPE_FLOAT,
	"range": TYPE_FLOAT,
	"recoil_pitch_degrees": TYPE_FLOAT,
	"recoil_yaw_degrees": TYPE_FLOAT,
	"kick_back": TYPE_FLOAT,
	"kick_return": TYPE_FLOAT,
	"recoil_recovery": TYPE_FLOAT,
	"recoil_recovery_share": TYPE_FLOAT,
	"ads_spread_multiplier": TYPE_FLOAT,
	"ads_zoom": TYPE_FLOAT,
}

@export var weapon_id: String = "rifle"

## Set before adding to the tree to override `weapons.json` with a gun's assembled stats
## (fire rate, damage, magazine, recoil ...); the feel values still come from the file.
var stats: Dictionary = {}
## The player carrying this weapon. Set by the weapons module when it equips.
var holder: PlayerController
var rules := WeaponRules.new()

var _recoil_rng := RandomNumberGenerator.new()
## On a client, the server's word on this gun's magazine; the rules only run on the server.
var _synced_ammo := -1
var _synced_reloading := false
var _sent := Vector2i(-1, -1)
## Recoil applied to the view that has not yet been pulled back.
var _recoil_debt := Vector2.ZERO


func _ready() -> void:
	# Net's session report reads the local player's rounds through this group.
	add_to_group(&"held_weapons")
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not (data as Dictionary).has(weapon_id):
		Log.error(&"weapons", "%s: no weapon '%s'" % [CONFIG, weapon_id])
		set_physics_process(false)
		return
	stats = (data[weapon_id] as Dictionary).merged(stats, true)
	if not Data.require(CONFIG, stats, REQUIRED):
		set_physics_process(false)
		return
	# Seeded per weapon so server and owning client roll the same spread.
	rules.setup(stats["rounds_per_minute"], int(stats["magazine"]), stats["reload_seconds"], deg_to_rad(stats["spread_degrees"]), get_instance_id())


## Rounds left. Clients show what the server last told them; only the server fires.
func ammo() -> int:
	if not multiplayer.is_server() and _synced_ammo >= 0:
		return _synced_ammo
	return rules.ammo()


func is_reloading() -> bool:
	if not multiplayer.is_server() and _synced_ammo >= 0:
		return _synced_reloading
	return rules.is_reloading()


func _physics_process(delta: float) -> void:
	rules.tick(delta)
	if holder == null:
		return
	_sync_magazine()
	var intent := holder.intent()
	if intent.consume_reload():
		request_reload()
	if intent.fire:
		request_fire(global_transform.origin, -global_transform.basis.z)
	else:
		_recover_recoil(delta)


## Server: tells the owning client about its magazine whenever it changes, so their ammo
## counter and RELOADING are right. Without this a client only knows its own copy, which
## never fires.
func _sync_magazine() -> void:
	if not multiplayer.is_server() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	var owner_peer := int(holder.get_meta(&"peer_id", 1))
	if owner_peer == multiplayer.get_unique_id() or not multiplayer.get_peers().has(owner_peer):
		return
	var now := Vector2i(rules.ammo(), 1 if rules.is_reloading() else 0)
	if now == _sent:
		return
	_sent = now
	_receive_magazine.rpc_id(owner_peer, now.x, now.y == 1)


@rpc("authority", "call_remote", "reliable")
func _receive_magazine(rounds: int, reloading: bool) -> void:
	_synced_ammo = rounds
	_synced_reloading = reloading


## Between bursts the view drifts back toward where it was aimed, so tapping stays on
## target while long sprays still climb.
func _recover_recoil(delta: float) -> void:
	if _recoil_debt.is_zero_approx():
		return
	var step := _recoil_debt * (1.0 - exp(-float(stats["recoil_recovery"]) * delta))
	_recoil_debt -= step
	holder.intent().look_delta -= step


## Client entry point. Without a network peer the local instance is the server, so this
## goes straight to server_fire; #9 to #11 route it through an RPC and the journal.
func request_fire(origin: Vector3, direction: Vector3) -> void:
	if multiplayer.is_server():
		server_fire(origin, direction)


func request_reload() -> void:
	if multiplayer.is_server():
		rules.start_reload()


## Server only: applies fire rules, traces the shot and damages what it hits.
func server_fire(origin: Vector3, direction: Vector3) -> void:
	if not rules.try_fire():
		return
	var spread := rules.last_spread()
	if holder != null and holder.intent().aim:
		spread *= float(stats["ads_spread_multiplier"])
	var basis := Basis.looking_at(direction)
	var dir := (basis * Vector3(tan(spread.x), tan(spread.y), -1.0)).normalized()
	var to := origin + dir * float(stats["range"])
	var exclude: Array[RID] = []
	if holder != null:
		exclude.append(holder.get_rid())
	var query := PhysicsRayQueryParameters3D.create(origin, to, 0xFFFFFFFF, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var hit_point := to
	var damage := 0.0
	var target: Node = null
	var collider: Object = null
	if not hit.is_empty():
		hit_point = hit["position"]
		collider = hit["collider"]
		var health := HealthComponent.find_on(collider as Node) if collider is Node else null
		if health != null:
			damage = health.server_apply_damage(stats["damage"], holder)
			target = health.get_parent()
	var target_path := String(target.get_path()) if target != null else ""
	var collider_path := String((collider as Node).get_path()) if collider is Node else ""
	# Decided here; replayed everywhere (this instance included) for effects and craters.
	_replay_shot.rpc(origin, hit_point, damage, target_path, collider_path)


## Runs on the server and every client: publishes `weapon.fired` locally (tracers, hit
## markers, craters) and kicks the aim on the instance that owns this player.
@rpc("authority", "call_local", "reliable")
func _replay_shot(origin: Vector3, hit_point: Vector3, damage: float, target_path: String, collider_path: String) -> void:
	var target: Node = get_node_or_null(target_path) if not target_path.is_empty() else null
	var collider: Node = get_node_or_null(collider_path) if not collider_path.is_empty() else null
	_play_shot_effects()
	# `collider` lets other modules react to what was hit (the world digs into terrain).
	EventBus.publish(&"weapon.fired", {"weapon": self, "holder": holder, "from": origin, "to": hit_point, "target": target, "collider": collider, "damage": damage})


## True on the one instance whose player is holding this weapon (solo, or that client).
func _held_locally() -> bool:
	if holder == null or not Net.has_local_player():
		return false
	return int(holder.get_meta(&"peer_id", Net.local_peer_id())) == Net.local_peer_id()


## Recoil for the shooter's own view. The gun's visible kick is ShotEffects.
func _play_shot_effects() -> void:
	if _held_locally():
		var pitch := deg_to_rad(stats["recoil_pitch_degrees"])
		var yaw := deg_to_rad(stats["recoil_yaw_degrees"]) * _recoil_rng.randf_range(-1.0, 1.0)
		# Negative y looks up: the controller pitches down for positive look_delta.y.
		var kick := Vector2(yaw, -pitch)
		holder.intent().look_delta += kick
		_recoil_debt += kick * float(stats["recoil_recovery_share"])

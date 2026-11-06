class_name HitscanWeapon
extends Node3D
## A carried hitscan gun. Reads the holder's PlayerIntent; the server decides every hit.
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
}

@export var weapon_id: String = "rifle"
@export var model_path: NodePath

var stats: Dictionary = {}
## The player carrying this weapon. Set by the weapons module when it equips.
var holder: PlayerController
var rules := WeaponRules.new()

var _model: Node3D
var _model_rest: Vector3
var _recoil_rng := RandomNumberGenerator.new()
## Recoil applied to the view that has not yet been pulled back.
var _recoil_debt := Vector2.ZERO


func _ready() -> void:
	_model = get_node_or_null(model_path)
	if _model != null:
		_model_rest = _model.position
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not (data as Dictionary).has(weapon_id):
		Log.error(&"weapons", "%s: no weapon '%s'" % [CONFIG, weapon_id])
		set_physics_process(false)
		return
	stats = data[weapon_id]
	if not Data.require(CONFIG, stats, REQUIRED):
		set_physics_process(false)
		return
	# Seeded per weapon so server and owning client roll the same spread.
	rules.setup(stats["rounds_per_minute"], int(stats["magazine"]), stats["reload_seconds"], deg_to_rad(stats["spread_degrees"]), get_instance_id())


func ammo() -> int:
	return rules.ammo()


func _physics_process(delta: float) -> void:
	rules.tick(delta)
	if _model != null:
		_model.position = _model.position.lerp(_model_rest, 1.0 - exp(-float(stats["kick_return"]) * delta))
	if holder == null:
		return
	var intent := holder.intent()
	if intent.consume_reload():
		request_reload()
	if intent.fire:
		request_fire(global_transform.origin, -global_transform.basis.z)
	else:
		_recover_recoil(delta)


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
	_play_shot_effects(hit_point, damage > 0.0)
	# `collider` lets other modules react to what was hit (the world digs into terrain).
	EventBus.publish(&"weapon.fired", {"weapon": self, "holder": holder, "from": origin, "to": hit_point, "target": target, "collider": collider, "damage": damage})


## Recoil and kick for the shooter. Replayed to other clients once networking lands.
func _play_shot_effects(_hit_point: Vector3, _hit_something: bool) -> void:
	if holder != null:
		var pitch := deg_to_rad(stats["recoil_pitch_degrees"])
		var yaw := deg_to_rad(stats["recoil_yaw_degrees"]) * _recoil_rng.randf_range(-1.0, 1.0)
		# Negative y looks up: the controller pitches down for positive look_delta.y.
		var kick := Vector2(yaw, -pitch)
		holder.intent().look_delta += kick
		_recoil_debt += kick * float(stats["recoil_recovery_share"])
	if _model != null:
		_model.position.z += float(stats["kick_back"])

class_name RocketLauncher
extends HitscanWeapon
## A launcher: a gun whose receiver fires projectiles (`projectile` on the receiver part), so
## it keeps every gun rule (one rocket a load, a slow reload, recoil, the HUD) and only changes
## what pulling the trigger does: a rocket leaves the tube (see `Rocket`) and a backblast
## lashes out behind. Rocket and backblast numbers are in weapons.json `rocket`.

## The weapons module, which spawns rockets so every instance sees them fly.
var rockets_parent: Node


## Server only: launches a rocket along the aim, from the eye like a shot, and hurts whoever
## stands in the backblast.
func server_fire(origin: Vector3, direction: Vector3) -> void:
	if holder != null and holder.get_meta(&"dead", false):
		return
	if not rules.try_fire():
		return
	var cfg := rocket_config()
	var dir := direction.normalized()
	# Out of the tube a little ahead of the eye, so it never starts inside the shooter.
	var start := origin + dir * 0.6
	if rockets_parent != null and rockets_parent.has_method(&"spawn_rocket"):
		rockets_parent.call(&"spawn_rocket", start, dir * float(cfg.get("speed", 55.0)), holder)
	_server_backblast(origin, dir, cfg.get("backblast", {}))
	_replay_launch.rpc(origin, dir)


## Everyone in the cone behind the tube takes the backblast, less the further away.
func _server_backblast(origin: Vector3, dir: Vector3, cfg: Dictionary) -> void:
	var reach := float(cfg.get("range", 4.0))
	var cone := float(cfg.get("cone_dot", 0.6))
	var damage := float(cfg.get("damage", 30.0))
	for group: StringName in [&"players", &"enemies"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body == null or body == holder:
				continue
			var to := body.global_position + Vector3.UP * 1.2 - origin
			if to.length() > reach or to.length() < 0.01 or to.normalized().dot(-dir) < cone:
				continue
			var health := HealthComponent.find_on(body)
			if health != null:
				health.server_apply_damage(damage * (1.0 - to.length() / reach), holder)


## Everywhere: the launch, for the shooter's recoil and everyone's sound and smoke.
@rpc("authority", "call_local", "reliable")
func _replay_launch(origin: Vector3, dir: Vector3) -> void:
	_play_shot_effects()
	EventBus.publish(&"weapons.rocket_launched", {"weapon": self, "holder": holder, "from": origin, "direction": dir})


static func rocket_config() -> Dictionary:
	var data: Variant = Data.load_json(CONFIG)
	return (data as Dictionary).get("rocket", {}) if data is Dictionary else {}

extends Node
## Equips spawned players with a rifle: its logic at the camera (shots follow the aim) and
## its one visible model in the body's hands, which the owner sees in first person and
## everyone else in third. Adds shot effects for all shots and the HUD for the local player.

const RIFLE := "res://modules/weapons/scenes/rifle.tscn"

var _charge_spawner := MultiplayerSpawner.new()
var _charges_placed := 0


func _ready() -> void:
	# Placed charges are created by the server and replicated, so everyone sees them blink.
	_charge_spawner.name = "ChargeSpawner"
	_charge_spawner.spawn_path = NodePath("..")
	_charge_spawner.spawn_function = _make_charge
	add_child(_charge_spawner)
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	if DisplayServer.get_name() != "headless":
		var effects := ExplosionEffects.new()
		effects.name = "ExplosionEffects"
		add_child(effects)
		var shots := ShotEffects.new()
		shots.name = "ShotEffects"
		add_child(shots)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)


func _on_player_spawned(p: Dictionary) -> void:
	var player: PlayerController = p["player"]
	# Every instance assembles the same default build for now; per-player loadouts come
	# with the modding screen (#66), when the server will send each player's build.
	var build_name := GunAssembly.chosen_build()
	var assembled := GunAssembly.assemble_named(build_name)
	if not assembled["ok"]:
		Log.error(&"weapons", "build %s does not work: %s" % [build_name, assembled["errors"]])
		return
	var rifle: HitscanWeapon = (load(RIFLE) as PackedScene).instantiate()
	rifle.holder = player
	rifle.stats = assembled["stats"]
	# At the camera, so shots start at the eye and follow the view.
	player.get_node("Head/Camera").add_child(rifle)
	var thrower := ChargeThrower.new()
	thrower.name = "ChargeThrower"
	thrower.holder = player
	thrower.charges_parent = self
	player.add_child(thrower)
	var socket := PlayerBody.weapon_socket(player)
	if socket != null:
		var held := GunAssembly.build_model(GunAssembly.build(build_name))
		held.name = "HeldRifle"
		# The optic's eye point carries how much it zooms and how fast this gun aims.
		var sight := held.get_node_or_null("Sight")
		if sight != null:
			sight.set_meta(&"zoom", float(rifle.stats.get("ads_zoom", 1.0)))
			sight.set_meta(&"ads_seconds", float(rifle.stats.get("ads_seconds", 0.2)))
			sight.set_meta(&"magnification", float(rifle.stats.get("magnification", 1.0)))
		socket.add_child(held)
	if DisplayServer.get_name() == "headless":
		return
	if p.get("local", false):
		var held_rifle := ShotEffects.held_rifle(player)
		if held_rifle != null and held_rifle.get_node_or_null("Lens") != null:
			var scope := ScopeView.new()
			scope.name = "ScopeView"
			scope.player = player
			scope.gun = held_rifle
			player.add_child(scope)
		var feedback := ShotFeedback.new()
		feedback.name = "ShotFeedback"
		feedback.local_player = player
		add_child(feedback)


## Server only, called by ChargeThrower.
func spawn_charge(at: Vector3, stats: Dictionary) -> DemolitionCharge:
	_charges_placed += 1
	return _charge_spawner.spawn({"index": _charges_placed, "position": at, "stats": stats})


## Runs on the server and, through the spawner, on every client.
func _make_charge(data: Variant) -> Node:
	var info: Dictionary = data
	var charge := DemolitionCharge.new()
	charge.name = "Charge%d" % int(info["index"])
	charge.stats = info["stats"]
	charge.position = info["position"]
	return charge

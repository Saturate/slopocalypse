extends Node
## Equips spawned players with a rifle: its logic at the camera (shots follow the aim) and
## its one visible model in the body's hands, which the owner sees in first person and
## everyone else in third. Each player's build (parts in slots) is decided by the server
## and replayed to everyone. Adds shot effects for all shots, and the HUD and modding
## screen for the local player.

const RIFLE := "res://modules/weapons/scenes/rifle.tscn"

var _charge_spawner := MultiplayerSpawner.new()
var _charges_placed := 0
## Peer id -> slot -> part id, for players who changed their gun; everyone else carries the
## default. Kept on every instance so players spawned later get the right gun.
var _builds: Dictionary = {}
var _local_player: PlayerController


func _ready() -> void:
	# Placed charges are created by the server and replicated, so everyone sees them blink.
	_charge_spawner.name = "ChargeSpawner"
	_charge_spawner.spawn_path = NodePath("..")
	_charge_spawner.spawn_function = _make_charge
	add_child(_charge_spawner)
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	EventBus.subscribe(&"weapons.build_changed", _on_build_changed)
	Net.peer_joined.connect(_on_peer_joined)
	if DisplayServer.get_name() != "headless":
		var data: Variant = Data.load_json(HitscanWeapon.CONFIG)
		if data is Dictionary:
			InputBindings.register((data as Dictionary).get("bindings", {}), &"weapons")
		var effects := ExplosionEffects.new()
		effects.name = "ExplosionEffects"
		add_child(effects)
		var shots := ShotEffects.new()
		shots.name = "ShotEffects"
		add_child(shots)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)
	EventBus.unsubscribe(&"weapons.build_changed", _on_build_changed)
	if Net.peer_joined.is_connected(_on_peer_joined):
		Net.peer_joined.disconnect(_on_peer_joined)


func _on_player_spawned(p: Dictionary) -> void:
	var player: PlayerController = p["player"]
	var thrower := ChargeThrower.new()
	thrower.name = "ChargeThrower"
	thrower.holder = player
	thrower.charges_parent = self
	player.add_child(thrower)
	var local: bool = p.get("local", false)
	if local:
		_local_player = player
	_equip(player, build_of(int(player.get_meta(&"peer_id", 1))))
	if DisplayServer.get_name() == "headless" or not local:
		return
	var feedback := ShotFeedback.new()
	feedback.name = "ShotFeedback"
	feedback.local_player = player
	add_child(feedback)
	var modding := ModdingScreen.new()
	modding.name = "ModdingScreen"
	modding.weapons = self
	modding.player = player
	add_child(modding)


## The build `peer` carries: theirs once they have changed it, otherwise the default.
func build_of(peer: int) -> Dictionary:
	return _builds.get(peer, GunAssembly.build(GunAssembly.chosen_build()))


## Client: asks the server to change this player's gun. The answer arrives as a
## `weapons.build_changed` replay, or not at all if the server refuses.
func request_build(slots: Dictionary) -> void:
	if multiplayer.is_server():
		server_set_build(multiplayer.get_unique_id(), slots)
	else:
		_request_build.rpc_id(1, slots)


@rpc("any_peer", "call_remote", "reliable")
func _request_build(slots: Dictionary) -> void:
	if multiplayer.is_server():
		server_set_build(multiplayer.get_remote_sender_id(), slots)


## Server: checks the build with the Rust rules and, if it works, makes it this peer's gun
## everywhere. Returns false (and logs why) for a build that does not assemble.
func server_set_build(peer: int, slots: Dictionary) -> bool:
	var clean := {}
	for slot: Variant in slots:
		if slot is String and slots[slot] is String:
			clean[slot] = slots[slot]
	var result := WeaponBuild.assemble(GunAssembly.catalogue(), clean)
	if not result["ok"]:
		Log.warn(&"weapons", "peer %d: build refused: %s" % [peer, ", ".join(result["errors"])])
		return false
	Net.server_broadcast(&"weapons.build_changed", {"peer": peer, "build": clean})
	return true


## Everywhere, from the server's broadcast or a late-join catch-up: remember the build and
## re-equip that player if they are here.
func _on_build_changed(p: Dictionary) -> void:
	var peer := int(p.get("peer", 0))
	var slots: Dictionary = p.get("build", {})
	_builds[peer] = slots
	for player: Node in get_tree().get_nodes_in_group(&"players"):
		if int(player.get_meta(&"peer_id", 1)) == peer:
			_equip(player as PlayerController, slots)


## Server: a player who joins late learns everyone's builds before their players appear.
func _on_peer_joined(peer: int) -> void:
	if not multiplayer.is_server():
		return
	for owner: int in _builds:
		_catch_up.rpc_id(peer, owner, _builds[owner])


@rpc("authority", "call_remote", "reliable")
func _catch_up(owner: int, slots: Dictionary) -> void:
	_on_build_changed({"peer": owner, "build": slots})


## Gives `player` the gun `slots` describes: its logic at the camera (shots start at the eye
## and follow the view) and its one visible model in the hands. Replaces any gun they had;
## the new one starts reloading, so swapping parts is never a free reload.
func _equip(player: PlayerController, slots: Dictionary) -> void:
	var assembled := WeaponBuild.assemble(GunAssembly.catalogue(), slots)
	if not assembled["ok"]:
		Log.error(&"weapons", "a build does not work: %s" % [assembled["errors"]])
		return
	var camera := player.get_node("Head/Camera")
	var had_gun := false
	for old in camera.get_children():
		if old is HitscanWeapon:
			had_gun = true
			camera.remove_child(old)
			old.queue_free()
	var rifle: HitscanWeapon = (load(RIFLE) as PackedScene).instantiate()
	rifle.holder = player
	rifle.stats = assembled["stats"]
	camera.add_child(rifle)
	if had_gun:
		rifle.rules.start_empty_reload()
	var socket := PlayerBody.weapon_socket(player)
	if socket != null:
		var old_held := socket.get_node_or_null("HeldRifle")
		if old_held != null:
			socket.remove_child(old_held)
			old_held.queue_free()
		var held := GunAssembly.build_model(slots)
		held.name = "HeldRifle"
		# The optic's eye point carries how much it zooms and how fast this gun aims.
		var sight := held.get_node_or_null("Sight")
		if sight != null:
			# A scope zooms the whole view by its magnification once it is up to the eye.
			var magnification := float(rifle.stats.get("magnification", 1.0))
			sight.set_meta(&"zoom", magnification if magnification > 1.0 else float(rifle.stats.get("ads_zoom", 1.0)))
			sight.set_meta(&"ads_seconds", float(rifle.stats.get("ads_seconds", 0.2)))
			sight.set_meta(&"magnification", float(rifle.stats.get("magnification", 1.0)))
		socket.add_child(held)
	if player == _local_player and DisplayServer.get_name() != "headless":
		_update_scope(player)


func _update_scope(player: PlayerController) -> void:
	var old := player.get_node_or_null("ScopeView")
	if old != null:
		player.remove_child(old)
		old.queue_free()
	var held := ShotEffects.held_rifle(player)
	var sight := held.get_node_or_null("Sight") if held != null else null
	if sight != null and float(sight.get_meta(&"magnification", 1.0)) > 1.0:
		var scope := ScopeView.new()
		scope.name = "ScopeView"
		scope.player = player
		scope.gun = held
		player.add_child(scope)


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

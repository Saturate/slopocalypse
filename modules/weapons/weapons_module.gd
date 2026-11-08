extends Node
## Equips spawned players with two guns, a primary (rifle) and a secondary (pistol): their
## logic at the camera (shots follow the aim), and the drawn one's model in the body's
## hands, which the owner sees in first person and everyone else in third. 1 and 2 switch. Each player's build (parts in slots) is decided by the server
## and replayed to everyone. Adds shot effects for all shots, and the HUD and modding
## screen for the local player.

const RIFLE := "res://modules/weapons/scenes/rifle.tscn"
## Weapon slots, in the order 1 and 2 select them.
const WEAPON_SLOTS: Array[String] = ["primary", "secondary"]

var _charge_spawner := MultiplayerSpawner.new()
var _charges_placed := 0
## Peer id -> slot -> part id, for players who changed their gun; everyone else carries the
## default. Kept on every instance so players spawned later get the right gun.
var _builds: Dictionary = {}
var _local_player: PlayerController


func _ready() -> void:
	# Other modules (saving) find the API through this group instead of a path.
	add_to_group(&"weapons_api")
	# Placed charges are created by the server and replicated, so everyone sees them blink.
	_charge_spawner.name = "ChargeSpawner"
	_charge_spawner.spawn_path = NodePath("..")
	_charge_spawner.spawn_function = _make_charge
	add_child(_charge_spawner)
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	EventBus.subscribe(&"weapons.build_changed", _on_build_changed)
	EventBus.subscribe(&"inventory.loot_spawned", _on_loot_spawned)
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
	EventBus.unsubscribe(&"inventory.loot_spawned", _on_loot_spawned)
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
	var peer := int(player.get_meta(&"peer_id", 1))
	for slot: String in WEAPON_SLOTS:
		_equip(player, build_of(peer, slot))
	if DisplayServer.get_name() == "headless" or not local:
		return
	var feedback := ShotFeedback.new()
	feedback.name = "ShotFeedback"
	feedback.local_player = player
	add_child(feedback)
	var modding := ModdingScreen.new()
	modding.name = "ModdingScreen"
	modding.weapons = self
	modding.peer = int(player.get_meta(&"peer_id", 1))
	modding.player = player
	add_child(modding)


## The build `peer` carries in a weapon slot ("primary" or "secondary"): theirs once they
## have changed it, otherwise the default for that slot.
func build_of(peer: int, slot: String = "primary") -> Dictionary:
	var theirs: Dictionary = _builds.get(peer, {})
	if theirs.has(slot):
		return theirs[slot]
	return GunAssembly.build(GunAssembly.chosen_build() if slot == "primary" else GunAssembly.default_secondary())


## The slot the player has drawn.
static func drawn_slot(player: Node) -> String:
	return WEAPON_SLOTS[clampi(int((player as PlayerController).intent().weapon_slot), 0, WEAPON_SLOTS.size() - 1)]


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
		_refuse(peer, ", ".join(result["errors"]))
		return false
	var why := _swap_parts(peer, build_of(peer, GunAssembly.weapon_slot_of(clean)), clean)
	if not why.is_empty():
		_refuse(peer, why)
		return false
	Net.server_broadcast(&"weapons.build_changed", {"peer": peer, "build": clean})
	return true


## Server: logs a refused build and tells the player why, so the modding screen can show it
## instead of the change silently not happening.
func _refuse(peer: int, why: String) -> void:
	Log.warn(&"weapons", "peer %d: build refused: %s" % [peer, why])
	if peer == multiplayer.get_unique_id():
		_build_refused(why)
	elif peer in multiplayer.get_peers():
		_build_refused.rpc_id(peer, why)


@rpc("authority", "call_remote", "reliable")
func _build_refused(why: String) -> void:
	EventBus.publish(&"weapons.build_refused", {"reason": why})


## Server: the builds `peer` changed from the defaults, `{weapon_slot: {part_slot: part}}`,
## for saving. Slots left at the default are not listed, so they follow the data.
func server_builds_of(peer: int) -> Dictionary:
	return (_builds.get(peer, {}) as Dictionary).duplicate(true)


## Server: gives `peer` back saved builds without touching their inventory (the parts were
## on the gun when it was saved). A build the current parts data no longer assembles is
## skipped, leaving that slot at its default.
func server_restore_builds(peer: int, builds: Dictionary) -> void:
	for weapon_slot: Variant in builds:
		var slots: Dictionary = builds[weapon_slot] if builds[weapon_slot] is Dictionary else {}
		var result := WeaponBuild.assemble(GunAssembly.catalogue(), slots)
		if not result["ok"]:
			Log.warn(&"weapons", "peer %d: saved %s build no longer assembles (%s); using the default" % [peer, weapon_slot, ", ".join(result["errors"])])
			continue
		Net.server_broadcast(&"weapons.build_changed", {"peer": peer, "build": slots})


## A gun part lying on the ground looks like the part, lying on its side.
func _on_loot_spawned(p: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var part: Dictionary = GunAssembly.catalogue().get(str(p.get("item", "")), {})
	var loot: Node = p.get("loot")
	if part.is_empty() or loot == null or not loot.has_method(&"set_visual"):
		return
	var model := MeshInstance3D.new()
	model.mesh = GunPartMeshes.mesh(str(part.get("mesh", "")))
	if model.mesh == null:
		return
	# Gun space has the part standing up; lay it on its side on the ground.
	model.rotation = Vector3(0.0, 0.0, PI / 2.0)
	model.position.y = 0.03
	loot.call(&"set_visual", model)


## The inventory module's API when it is loaded; without it every part is free to use.
func inventory() -> Node:
	return get_tree().get_first_node_in_group(&"inventory_api")


## Parts the change from `before` to `after` puts on the gun (they must come from the
## inventory) and takes off (they go back into it).
static func part_changes(before: Dictionary, after: Dictionary) -> Dictionary:
	var fitted: Array[String] = []
	var removed: Array[String] = []
	var slots := before.keys()
	for slot: Variant in after:
		if not slots.has(slot):
			slots.append(slot)
	for slot: Variant in slots:
		var was := str(before.get(slot, ""))
		var now := str(after.get(slot, ""))
		if was == now:
			continue
		if not now.is_empty():
			fitted.append(now)
		if not was.is_empty():
			removed.append(was)
	return {"fitted": fitted, "removed": removed}


## Server: takes the parts a build change fits out of the inventory and puts the removed
## ones back. Returns why it cannot (a part not owned, no room for what comes off), having
## changed nothing; "" when done.
func _swap_parts(peer: int, before: Dictionary, after: Dictionary) -> String:
	var inv := inventory()
	if inv == null:
		return ""
	var changes := part_changes(before, after)
	var fitted: Array[String] = changes["fitted"]
	var removed: Array[String] = changes["removed"]
	var needed := {}
	for part in fitted:
		needed[part] = int(needed.get(part, 0)) + 1
	for part: String in needed:
		if int(inv.call(&"count", peer, part)) < int(needed[part]):
			return "%s is not in your backpack" % str((GunAssembly.catalogue().get(part, {}) as Dictionary).get("name", part))
	var taken: Array[String] = []
	for part in fitted:
		inv.call(&"server_take", peer, part)
		taken.append(part)
	var given: Array[String] = []
	for part in removed:
		if not inv.call(&"server_give", peer, part):
			# Undo: what came off goes back on, what was fitted goes back in the bag.
			for g in given:
				inv.call(&"server_take", peer, g)
			for t in taken:
				inv.call(&"server_give", peer, t)
			return "no room in the inventory for %s" % part
		given.append(part)
	return ""


## Everywhere, from the server's broadcast or a late-join catch-up: remember the build and
## re-equip that player if they are here.
func _on_build_changed(p: Dictionary) -> void:
	var peer := int(p.get("peer", 0))
	var slots: Dictionary = p.get("build", {})
	if not _builds.has(peer):
		_builds[peer] = {}
	_builds[peer][GunAssembly.weapon_slot_of(slots)] = slots
	for player: Node in get_tree().get_nodes_in_group(&"players"):
		if int(player.get_meta(&"peer_id", 1)) == peer:
			_equip(player as PlayerController, slots)


## Server: a player who joins late learns everyone's builds before their players appear.
func _on_peer_joined(peer: int) -> void:
	if not multiplayer.is_server():
		return
	for owner: int in _builds:
		for slot: String in _builds[owner]:
			_catch_up.rpc_id(peer, owner, _builds[owner][slot])


@rpc("authority", "call_remote", "reliable")
func _catch_up(owner: int, slots: Dictionary) -> void:
	_on_build_changed({"peer": owner, "build": slots})


## Gives `player` the gun `slots` describes, in the weapon slot its receiver belongs to: its
## logic at the camera (shots start at the eye and follow the view), and, if that slot is
## drawn, its model in the hands. Replaces the gun in that slot; a replacement starts
## reloading, so swapping parts is never a free reload.
func _equip(player: PlayerController, slots: Dictionary) -> void:
	var assembled := WeaponBuild.assemble(GunAssembly.catalogue(), slots)
	if not assembled["ok"]:
		Log.error(&"weapons", "a build does not work: %s" % [assembled["errors"]])
		return
	var slot := GunAssembly.weapon_slot_of(slots)
	var camera := player.get_node("Head/Camera")
	var node_name := "Weapon_" + slot
	var old := camera.get_node_or_null(node_name)
	if old != null:
		camera.remove_child(old)
		old.queue_free()
	var weapon: HitscanWeapon = (load(RIFLE) as PackedScene).instantiate()
	weapon.name = node_name
	weapon.holder = player
	weapon.stats = assembled["stats"]
	weapon.semi_auto = GunAssembly.receiver_of(slots).get("fire_mode", "auto") == "semi"
	weapon.set_meta(&"build", slots)
	camera.add_child(weapon)
	if old != null:
		weapon.rules.start_empty_reload()
	weapon.active = drawn_slot(player) == slot
	if weapon.active:
		_hold(player, slot)


## Puts the drawn slot's gun in the hands and makes it the one that fires; the other waits.
func _draw(player: PlayerController, slot: String) -> void:
	var camera := player.get_node("Head/Camera")
	for s: String in WEAPON_SLOTS:
		var weapon := camera.get_node_or_null("Weapon_" + s) as HitscanWeapon
		if weapon != null:
			weapon.active = s == slot
			if weapon.active:
				weapon.start_draw()
	_hold(player, slot)


## The visible model in the hands for the gun in `slot`, set where its receiver says it is
## held, with the sight's ADS values on its marker.
func _hold(player: PlayerController, slot: String) -> void:
	player.set_meta(&"drawn", slot)
	var socket := PlayerBody.weapon_socket(player)
	var weapon := player.get_node("Head/Camera").get_node_or_null("Weapon_" + slot) as HitscanWeapon
	if socket == null or weapon == null:
		return
	var old_held := socket.get_node_or_null("HeldRifle")
	if old_held != null:
		socket.remove_child(old_held)
		old_held.queue_free()
	var slots: Dictionary = weapon.get_meta(&"build", {})
	var held := GunAssembly.build_model(slots)
	held.name = "HeldRifle"
	held.position = GunAssembly.hold_offset(slots)
	# The optic's eye point carries how much it zooms and how fast this gun aims.
	var sight := held.get_node_or_null("Sight")
	if sight != null:
		# A scope zooms the whole view by its magnification once it is up to the eye.
		var magnification := float(weapon.stats.get("magnification", 1.0))
		sight.set_meta(&"zoom", magnification if magnification > 1.0 else float(weapon.stats.get("ads_zoom", 1.0)))
		sight.set_meta(&"ads_seconds", float(weapon.stats.get("ads_seconds", 0.2)))
		sight.set_meta(&"magnification", magnification)
		# A pistol is aimed at arm's length and held out at the hip; the receiver says how far.
		var receiver := GunAssembly.receiver_of(slots)
		if receiver.has("eye_relief") and not sight.has_meta(&"eye_relief"):
			sight.set_meta(&"eye_relief", float(receiver["eye_relief"]))
		if receiver.has("hip_sight"):
			var hip: Array = receiver["hip_sight"]
			sight.set_meta(&"hip_sight", Vector3(float(hip[0]), float(hip[1]), float(hip[2])))
	socket.add_child(held)
	if player == _local_player and DisplayServer.get_name() != "headless":
		_update_scope(player)


func _physics_process(_delta: float) -> void:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as PlayerController
		if player == null or not player.has_node("Head/Camera"):
			continue
		var intent := player.intent()
		# The server decides which gun is out; the choice reaches clients with the intent.
		if multiplayer.is_server():
			if intent.consume_weapon_1():
				intent.weapon_slot = 0
			if intent.consume_weapon_2():
				intent.weapon_slot = 1
		var slot := drawn_slot(player)
		if player.get_meta(&"drawn", "") != slot:
			_draw(player, slot)


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

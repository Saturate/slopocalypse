extends Node
## Arms players with up to two guns, a primary (rifle) and a secondary (pistol): their logic
## at the camera (shots follow the aim), and the drawn one's model in the body's hands,
## which the owner sees in first person and everyone else in third. 1 and 2 switch. Each
## player's build (parts in slots) is decided by the server and replayed to everyone. With
## the inventory loaded, guns are items: whatever gun item is in a player's primary or
## secondary gear slot is the gun they hold, with the build stored on that item (so a looted
## rifle keeps its parts); an empty slot means no gun there. Without the inventory everyone
## carries the default guns. Adds shot effects for all shots, and the HUD and modding screen
## for the local player.

const RIFLE := "res://modules/weapons/scenes/rifle.tscn"
## Weapon slots, in the order 1 and 2 select them.
const WEAPON_SLOTS: Array[String] = ["primary", "secondary"]
## A bullet landing this close to a placed charge sets it off.
const CHARGE_SHOT_RADIUS := 0.35
## Gun items and the default build each comes with.
const GUN_ITEMS := {"gun_rifle": "primary", "gun_pistol": "secondary", "gun_rocket": "primary"}
## Gun items that aren't their slot's default gun, with the build they come as.
const ITEM_BUILDS := {"gun_rocket": "launcher"}

var _charge_spawner := MultiplayerSpawner.new()
var _rocket_spawner := MultiplayerSpawner.new()
var _rockets_fired := 0
var _charges_placed := 0
## Peer id -> slot -> part id, for players who changed their gun; everyone else carries the
## default. Kept on every instance so players spawned later get the right gun.
var _builds: Dictionary = {}
var _local_player: PlayerController

## Kept loaded: Godot's resource cache lets go of a scene once nothing holds it, and loading
## a generated scene again from text costs tens of milliseconds per spawn.
var _packed_scene: PackedScene


func _scene() -> PackedScene:
	if _packed_scene == null:
		_packed_scene = load(RIFLE)
	return _packed_scene


func _ready() -> void:
	# Other modules (saving) find the API through this group instead of a path.
	add_to_group(&"weapons_api")
	# Placed charges are created by the server and replicated, so everyone sees them blink.
	_charge_spawner.name = "ChargeSpawner"
	_charge_spawner.spawn_path = NodePath("..")
	_charge_spawner.spawn_function = _make_charge
	add_child(_charge_spawner)
	# Rockets in flight too: the server spawns them, every instance flies them.
	_rocket_spawner.name = "RocketSpawner"
	_rocket_spawner.spawn_path = NodePath("..")
	_rocket_spawner.spawn_function = _make_rocket
	add_child(_rocket_spawner)
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	EventBus.subscribe(&"weapons.build_changed", _on_build_changed)
	EventBus.subscribe(&"inventory.loot_spawned", _on_loot_spawned)
	EventBus.subscribe(&"inventory.item_model", _on_item_model)
	EventBus.subscribe(&"inventory.slot_changed", _on_slot_changed)
	EventBus.subscribe(&"weapon.fired", _on_shot_near_charge)
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
	EventBus.unsubscribe(&"inventory.item_model", _on_item_model)
	EventBus.unsubscribe(&"inventory.slot_changed", _on_slot_changed)
	EventBus.unsubscribe(&"weapon.fired", _on_shot_near_charge)
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
		var build := build_of(peer, slot)
		if not build.is_empty():
			_equip(player, build)
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


## The build `peer` carries in a weapon slot ("primary" or "secondary"): theirs once known
## (empty when that slot has no gun), otherwise the default for that slot.
func build_of(peer: int, slot: String = "primary") -> Dictionary:
	var theirs: Dictionary = _builds.get(peer, {})
	if theirs.has(slot):
		return theirs[slot]
	return default_build(slot)


static func default_build(slot: String) -> Dictionary:
	return GunAssembly.build(GunAssembly.chosen_build() if slot == "primary" else GunAssembly.default_secondary())


## The build a gun item carries: its own if it has one that assembles, else its default.
static func build_of_item(item: String, data: Dictionary) -> Dictionary:
	var own: Variant = data.get("build")
	if own is Dictionary and not (own as Dictionary).is_empty() and WeaponBuild.assemble(GunAssembly.catalogue(), own)["ok"]:
		return own
	if ITEM_BUILDS.has(item):
		return GunAssembly.build(str(ITEM_BUILDS[item]))
	return default_build(str(GUN_ITEMS.get(item, "primary")))


## Server: the gun in a player's gear slot changed: arm them with it (its own build) or, for
## an empty slot, take that gun away. Everyone hears it.
func _on_slot_changed(p: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var slot := str(p.get("slot", ""))
	var item := str(p.get("item", ""))
	var build := build_of_item(item, p.get("data", {})) if GUN_ITEMS.has(item) else {}
	Net.server_broadcast(&"weapons.build_changed", {"peer": int(p.get("peer", 0)), "slot": slot, "build": build})


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
	var weapon_slot := GunAssembly.weapon_slot_of(clean)
	var inv := inventory()
	if inv != null and (inv.call(&"slot_item", peer, weapon_slot) as Dictionary).is_empty():
		_refuse(peer, "no gun in your %s slot" % weapon_slot)
		return false
	var why := _swap_parts(peer, build_of(peer, weapon_slot), clean)
	if not why.is_empty():
		_refuse(peer, why)
		return false
	# The build lives on the gun item; that change re-arms the player.
	if inv != null:
		inv.call(&"server_set_slot_data", peer, weapon_slot, {"build": clean})
	else:
		Net.server_broadcast(&"weapons.build_changed", {"peer": peer, "slot": weapon_slot, "build": clean})
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
	# With the inventory, builds are saved on the gun items instead.
	if inventory() != null:
		return {}
	return (_builds.get(peer, {}) as Dictionary).duplicate(true)


## Server: gives `peer` back saved builds without touching their inventory (the parts were
## on the gun when it was saved). A build the current parts data no longer assembles is
## skipped, leaving that slot at its default.
func server_restore_builds(peer: int, builds: Dictionary) -> void:
	if inventory() != null:
		return
	for weapon_slot: Variant in builds:
		var slots: Dictionary = builds[weapon_slot] if builds[weapon_slot] is Dictionary else {}
		var result := WeaponBuild.assemble(GunAssembly.catalogue(), slots)
		if not result["ok"]:
			Log.warn(&"weapons", "peer %d: saved %s build no longer assembles (%s); using the default" % [peer, weapon_slot, ", ".join(result["errors"])])
			continue
		Net.server_broadcast(&"weapons.build_changed", {"peer": peer, "build": slots})


## A gun part lying on the ground looks like the part, lying on its side; a gun looks like
## that gun, with its own parts.
func _on_loot_spawned(p: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var loot: Node = p.get("loot")
	var item := str(p.get("item", ""))
	if GUN_ITEMS.has(item) and loot != null and loot.has_method(&"set_visual"):
		var gun := GunAssembly.build_model(build_of_item(item, loot.get_meta(&"data", {})))
		gun.rotation = Vector3(0.0, 0.0, PI / 2.0)
		gun.position.y = 0.05
		loot.call(&"set_visual", gun)
		return
	var part: Dictionary = GunAssembly.catalogue().get(item, {})
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


## The inventory wants a model of an item (for its icon): a gun part's own mesh, a whole
## gun in its default build, or a breaching charge's block.
func _on_item_model(p: Dictionary) -> void:
	if str(p.get("item", "")) == "breach_charge" and p.get("model") == null:
		p["model"] = _charge_model()
		return
	if GUN_ITEMS.has(str(p.get("item", ""))) and p.get("model") == null:
		p["model"] = GunAssembly.build_model(build_of_item(str(p["item"]), {}))
		return
	var part: Dictionary = GunAssembly.catalogue().get(str(p.get("item", "")), {})
	if part.is_empty() or p.get("model") != null:
		return
	var mesh := GunPartMeshes.mesh(str(part.get("mesh", "")))
	if mesh == null:
		return
	var model := MeshInstance3D.new()
	model.mesh = mesh
	p["model"] = model


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
## re-equip that player if they are here; an empty build takes the gun in that slot away.
func _on_build_changed(p: Dictionary) -> void:
	var peer := int(p.get("peer", 0))
	var slots: Dictionary = p.get("build", {})
	var slot := str(p.get("slot", "")) if slots.is_empty() else GunAssembly.weapon_slot_of(slots)
	if slot.is_empty():
		return
	if not _builds.has(peer):
		_builds[peer] = {}
	_builds[peer][slot] = slots
	for player: Node in _players_of(peer):
		if slots.is_empty():
			_unequip(player as PlayerController, slot)
		else:
			_equip(player as PlayerController, slots)


## Players (and soldiers) with this peer id.
func _players_of(peer: int) -> Array[Node]:
	var out: Array[Node] = []
	for group: StringName in [&"players", &"enemies"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if int(node.get_meta(&"peer_id", 1)) == peer and not out.has(node):
				out.append(node)
	return out


## Takes the gun in `slot` away: no logic at the camera, nothing in the hands if it was drawn.
func _unequip(player: PlayerController, slot: String) -> void:
	var camera := player.get_node("Head/Camera")
	var old := camera.get_node_or_null("Weapon_" + slot)
	if old != null:
		camera.remove_child(old)
		old.queue_free()
	if drawn_slot(player) == slot:
		var socket := PlayerBody.weapon_socket(player)
		var held := socket.get_node_or_null("HeldRifle") if socket != null else null
		if held != null:
			socket.remove_child(held)
			held.queue_free()


## Server: a player who joins late learns everyone's builds before their players appear.
func _on_peer_joined(peer: int) -> void:
	if not multiplayer.is_server():
		return
	for owner: int in _builds:
		for slot: String in _builds[owner]:
			_catch_up.rpc_id(peer, owner, slot, _builds[owner][slot])


@rpc("authority", "call_remote", "reliable")
func _catch_up(owner: int, slot: String, slots: Dictionary) -> void:
	_on_build_changed({"peer": owner, "slot": slot, "build": slots})


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
	# Already holding exactly this gun: nothing to do (and no forced reload).
	if old != null and old.get_meta(&"build", {}) == slots:
		return
	if old != null:
		camera.remove_child(old)
		old.queue_free()
	var weapon: HitscanWeapon = _scene().instantiate()
	# A receiver that fires projectiles (a launcher) gets the launcher's trigger.
	if bool(GunAssembly.receiver_of(slots).get("projectile", false)):
		weapon.set_script(RocketLauncher)
		weapon.set(&"rockets_parent", self)
	weapon.name = node_name
	weapon.holder = player
	weapon.stats = assembled["stats"]
	# Soldiers' guns hit softer than a player's (their module says how much).
	if player.has_meta(&"damage_scale"):
		weapon.stats["damage"] = float(weapon.stats.get("damage", 0.0)) * float(player.get_meta(&"damage_scale"))
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
	var prof := Prof.start()
	_physics_tick(_delta)
	Prof.stop(&"weapons/module:physics", prof)


func _physics_tick(_delta: float) -> void:
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
## Server: a bullet that hits a placed charge sets it off.
func _on_shot_near_charge(p: Dictionary) -> void:
	if not multiplayer.is_server() or not p.has("to"):
		return
	var hit: Vector3 = p["to"]
	for node: Node in get_tree().get_nodes_in_group(&"charges"):
		var charge := node as DemolitionCharge
		if charge != null and not charge.is_queued_for_deletion() and charge.global_position.distance_to(hit) < CHARGE_SHOT_RADIUS:
			charge.server_explode()


## Server only, called by RocketLauncher: a rocket flying from `at` at `velocity`.
func spawn_rocket(at: Vector3, velocity: Vector3, shooter: Node3D) -> Rocket:
	_rockets_fired += 1
	var rocket: Rocket = _rocket_spawner.spawn({"index": _rockets_fired, "position": at, "velocity": velocity, "cfg": RocketLauncher.rocket_config()})
	rocket.shooter = shooter
	return rocket


## Runs on the server and, through the spawner, on every client.
func _make_rocket(data: Variant) -> Node:
	var info: Dictionary = data
	var rocket := Rocket.new()
	rocket.name = "Rocket%d" % int(info["index"])
	rocket.position = info["position"]
	rocket.velocity = info["velocity"]
	rocket.cfg = info["cfg"]
	return rocket


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


## A block of putty in olive wrap with a detonator on top, for icons.
static func _charge_model() -> Node3D:
	var root := Node3D.new()
	var block := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.22, 0.08, 0.14)
	var wrap := StandardMaterial3D.new()
	wrap.albedo_color = Color(0.4, 0.42, 0.3)
	box.material = wrap
	block.mesh = box
	root.add_child(block)
	var cap := MeshInstance3D.new()
	var top := BoxMesh.new()
	top.size = Vector3(0.06, 0.03, 0.05)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.15, 0.15, 0.16)
	top.material = metal
	cap.mesh = top
	cap.position = Vector3(0.04, 0.055, 0.0)
	root.add_child(cap)
	return root

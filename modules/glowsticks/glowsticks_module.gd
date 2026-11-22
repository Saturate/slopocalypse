extends Node
## Glowsticks (#447). A glowstick is an inventory item (`glowstick`) you choose to carry.
## Cracking one (L, or a right click on it in the backpack) uses it up and lights it on your
## chest in your armband's colour: a bright stick with a small light, seen from far off in the
## dark but too weak to light a room. It burns `burn_seconds` and is then spent and gone.
## Stowing it (L again) hides the light; the chemistry cannot be stopped, so it keeps burning
## in the pocket and shows again with whatever time is left. Dropping it (K) leaves it
## glowing on the ground until it burns out; so does dying with one. Nobody shows one unless
## they cracked it, so going quiet means not carrying one lit.
##
## Soldiers: a share of them (`enemy_night_share`, rolled at spawn) carry one and hold it up
## at night while on patrol; a soldier fighting or chasing someone puts it away. Theirs do
## not run down; one who dies drops it lit.
##
## The server decides all of it; clients get `glowsticks.state` over Net.server_broadcast
## (who shows one, players' time left, sticks on the ground) whenever it changes and draw it
## (GlowstickView). A lit stick is not saved: a restart puts it out.

const ITEM := GlowstickRules.ITEM

var config: Dictionary = {}

var _rng := RandomNumberGenerator.new()
## Server: peer -> {left: seconds, shown: bool} for each player with a cracked stick.
var _lit: Dictionary[int, Dictionary] = {}
## Server: soldiers who carry one, rolled as they spawn.
var _soldiers: Array[Node] = []
## Server: peer id of each soldier showing theirs now.
var _soldiers_shown: Dictionary[int, bool] = {}
## Server: lit sticks on the ground, oldest first: {id, position, colour, left}.
var _ground: Array[Dictionary] = []
var _next_ground := 1
var _dirty := false
var _check_in := 0.0
var _send_in := 0.0
var _view: GlowstickView


func _ready() -> void:
	add_to_group(&"glowsticks_api")
	var data: Variant = Data.load_json(GlowstickRules.CONFIG)
	if not GlowstickRules.valid(data):
		set_physics_process(false)
		return
	config = data
	_rng.randomize()
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	EventBus.subscribe(&"player.died", _on_player_died)
	EventBus.subscribe(&"enemy.died", _on_enemy_died)
	EventBus.subscribe(&"glowsticks.use", _on_use)
	EventBus.subscribe(&"inventory.item_model", _on_item_model)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	if DisplayServer.get_name() != "headless":
		_view = GlowstickView.new()
		_view.name = "View"
		_view.config = config
		add_child(_view)


func _exit_tree() -> void:
	if config.is_empty():
		return
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)
	EventBus.unsubscribe(&"player.died", _on_player_died)
	EventBus.unsubscribe(&"enemy.died", _on_enemy_died)
	EventBus.unsubscribe(&"glowsticks.use", _on_use)
	EventBus.unsubscribe(&"inventory.item_model", _on_item_model)
	if Net.peer_joined.is_connected(_on_peer_joined):
		Net.peer_joined.disconnect(_on_peer_joined)
	if Net.peer_left.is_connected(_on_peer_left):
		Net.peer_left.disconnect(_on_peer_left)


## Server: L. Cracks a stick when none is lit, else stows or shows the lit one. Returns why
## it was refused, or "".
func server_toggle(peer: int) -> String:
	if _lit.has(peer):
		return server_stow(peer, bool(_lit[peer]["shown"]))
	return server_crack(peer)


## Server: uses up one glowstick from `peer`'s gear and lights it on their chest.
func server_crack(peer: int) -> String:
	var player := _player_of(peer)
	var why := ""
	var inventory := get_tree().get_first_node_in_group(&"inventory_api")
	if player == null or player.get_meta(&"dead", false):
		why = "no living player"
	elif _lit.has(peer):
		why = "one is already lit"
	elif inventory == null or not bool(inventory.call(&"server_take", peer, ITEM)):
		why = "no glowstick"
	if not why.is_empty():
		return _refused(peer, "crack", why)
	_lit[peer] = {"left": float(config["burn_seconds"]), "shown": true}
	Log.info(&"glowsticks", "peer %d cracked a glowstick" % peer)
	_changed()
	return ""


## Server: puts the lit stick away (`stowed`), or takes it out again. It burns either way.
func server_stow(peer: int, stowed: bool) -> String:
	if not _lit.has(peer):
		return _refused(peer, "stow" if stowed else "show", "nothing lit")
	_lit[peer]["shown"] = not stowed
	Log.info(&"glowsticks", "peer %d %s their glowstick" % [peer, "stowed" if stowed else "took out"])
	_changed()
	return ""


## Server: K. Lays the lit stick on the ground at `peer`'s feet, still burning.
func server_drop(peer: int) -> String:
	var player := _player_of(peer)
	if not _lit.has(peer):
		return _refused(peer, "drop", "nothing lit")
	if player == null:
		return _refused(peer, "drop", "no player")
	var at := player.global_position - player.global_transform.basis.z * float(config["drop_ahead"])
	_lay(at, GlowstickRules.colour_for(player), float(_lit[peer]["left"]))
	_lit.erase(peer)
	Log.info(&"glowsticks", "peer %d dropped their glowstick" % peer)
	_changed()
	return ""


## Server: what clients are told. `carriers`: peer id -> [shown, seconds left] (soldiers
## -1: theirs do not run down); `ground`: [id, position, colour] per stick on the ground.
func server_state() -> Dictionary:
	var carriers := {}
	for peer: int in _lit:
		carriers[peer] = [bool(_lit[peer]["shown"]), float(_lit[peer]["left"])]
	for peer: int in _soldiers_shown:
		carriers[peer] = [true, -1.0]
	var ground := []
	for g: Dictionary in _ground:
		ground.append([int(g["id"]), g["position"], g["colour"]])
	return {"carriers": carriers, "ground": ground}


## Server: `peer`'s lit stick as {left, shown}, or empty.
func lit_of(peer: int) -> Dictionary:
	return _lit.get(peer, {})


## Server: does this soldier carry one (whether or not it shows it now)?
func soldier_carries(soldier: Node) -> bool:
	return _soldiers.has(soldier)


func _physics_process(delta: float) -> void:
	var prof := Prof.start()
	_physics_tick(delta)
	Prof.stop(&"glowsticks/module:physics", prof)


func _physics_tick(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	_read_intents()
	_burn(delta)
	_check_in -= delta
	if _check_in <= 0.0:
		_check_in = float(config["check_seconds"])
		_check_soldiers()
	_send_in -= delta
	if _dirty and _send_in <= 0.0:
		_send_in = float(config["send_seconds"])
		_dirty = false
		Net.server_broadcast(&"glowsticks.state", server_state())


func _read_intents() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as PlayerController
		if player == null:
			continue
		var intent := player.intent()
		var toggle := intent.consume_glowstick()
		var drop := intent.consume_glowstick_drop()
		if player.get_meta(&"dead", false):
			continue
		var peer := int(player.get_meta(&"peer_id", 1))
		if toggle:
			server_toggle(peer)
		if drop:
			server_drop(peer)


func _burn(delta: float) -> void:
	for peer: int in _lit.keys():
		_lit[peer]["left"] = float(_lit[peer]["left"]) - delta
		if float(_lit[peer]["left"]) <= 0.0:
			_lit.erase(peer)
			Log.info(&"glowsticks", "peer %d's glowstick burned out" % peer)
			_changed()
	var i := 0
	while i < _ground.size():
		_ground[i]["left"] = float(_ground[i]["left"]) - delta
		if float(_ground[i]["left"]) <= 0.0:
			_ground.remove_at(i)
			_changed()
		else:
			i += 1


func _check_soldiers() -> void:
	var night := _is_night()
	var shown: Dictionary[int, bool] = {}
	var enemies := get_tree().get_first_node_in_group(&"enemies_api")
	# A typed filter lambda errors on a freed entry and returns nothing (missions free their
	# guards without a death), so freed ones are dropped by hand.
	var alive: Array[Node] = []
	for soldier: Variant in _soldiers:
		if is_instance_valid(soldier) and not (soldier as Node).is_queued_for_deletion():
			alive.append(soldier as Node)
	_soldiers = alive
	for soldier: Node in _soldiers:
		if soldier.get_meta(&"dead", false) or soldier.get_meta(&"surrendered", false):
			continue
		var patrolling := enemies != null and bool(enemies.call(&"is_patrolling", soldier))
		if GlowstickRules.soldier_shows(true, night, patrolling):
			shown[int(soldier.get_meta(&"peer_id", 0))] = true
	if shown != _soldiers_shown:
		_soldiers_shown = shown
		_changed()


func _is_night() -> bool:
	var daytime := get_tree().get_first_node_in_group(&"daytime_api")
	var clock: Object = daytime.call(&"clock") if daytime != null else null
	return clock != null and bool(clock.call(&"is_night"))


func _lay(at: Vector3, colour: Color, left: float) -> void:
	_ground.append({"id": _next_ground, "position": at, "colour": colour, "left": left})
	_next_ground += 1
	while _ground.size() > int(config["ground_max"]):
		_ground.pop_front()


func _changed() -> void:
	_dirty = true


func _refused(peer: int, what: String, why: String) -> String:
	Log.info(&"glowsticks", "peer %d: %s refused: %s" % [peer, what, why])
	return why


func _player_of(peer: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if int(node.get_meta(&"peer_id", 1)) == peer:
			return node as Node3D
	return null


func _on_player_spawned(p: Dictionary) -> void:
	var person := p.get("player") as Node
	if person == null:
		return
	if multiplayer.is_server() and bool(p.get("npc", false)) and person.is_in_group(&"enemies"):
		if GlowstickRules.soldier_carries(_rng.randf(), float(config["enemy_night_share"])):
			_soldiers.append(person)
	if _view != null and bool(p.get("local", false)):
		_view.show_hud_for(person as Node3D)


## Server: a player who dies with a lit stick drops it where they fell.
func _on_player_died(p: Dictionary) -> void:
	var player := p.get("player") as Node3D
	if not multiplayer.is_server() or player == null:
		return
	var peer := int(player.get_meta(&"peer_id", 1))
	if not _lit.has(peer):
		return
	_lay(player.global_position, GlowstickRules.colour_for(player), float(_lit[peer]["left"]))
	_lit.erase(peer)
	_changed()


## Server: so does a soldier holding one up.
func _on_enemy_died(p: Dictionary) -> void:
	var soldier := p.get("enemy") as Node3D
	if not multiplayer.is_server() or soldier == null:
		return
	_soldiers.erase(soldier)
	var peer := int(soldier.get_meta(&"peer_id", 0))
	if _soldiers_shown.erase(peer):
		_lay(soldier.global_position, GlowstickRules.colour_for(soldier), float(config["enemy_drop_seconds"]))
		_changed()


## Server: a right click on a glowstick in the backpack (the inventory hands it over).
func _on_use(ask: Dictionary) -> void:
	if multiplayer.is_server() and str(ask.get("item", "")) == ITEM:
		ask["used"] = server_crack(int(ask.get("peer", 0))).is_empty()


## A spare stick's look, for its tile in the inventory.
func _on_item_model(ask: Dictionary) -> void:
	if str(ask.get("item", "")) == ITEM and ask.get("model") == null:
		ask["model"] = GlowstickView.stick(config, GlowstickRules.colour(config["spare_colour"]), 0.0)


func _on_peer_joined(_peer: int) -> void:
	_changed()


func _on_peer_left(peer: int) -> void:
	if _lit.erase(peer):
		_changed()

extends Node
## Client only: plays the game's sounds from events it hears on the bus, positioned in the
## world. Shots (rifle, pistol, suppressed) at the shooter, impacts where bullets land, a
## tick when your own shot hits, explosions, everyone's footsteps, and for your own player
## reload clicks, a pickup blip, a thump when hurt, plus quiet wind. Never changes game
## state. Sounds come from SoundBank; volumes are in data/audio.json.

const CONFIG := "res://modules/audio/data/audio.json"

## Off on a headless server; tests switch it on.
var enabled := DisplayServer.get_name() != "headless"
var config: Dictionary = {}

var _voices: Array[Node] = []
var _strides: Dictionary = {}
var _local: Node3D
var _last_health := -1.0
var _was_reloading := false
var _last_items := -1


func _ready() -> void:
	if not enabled:
		return
	var data: Variant = Data.load_json(CONFIG)
	config = data if data is Dictionary else {}
	EventBus.subscribe(&"weapon.fired", _on_fired)
	EventBus.subscribe(&"explosion", _on_explosion)
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	EventBus.subscribe(&"inventory.changed", _on_inventory_changed)
	var wind := AudioStreamPlayer.new()
	wind.name = "Wind"
	wind.stream = SoundBank.get_sound("wind")
	wind.volume_db = _volume("wind")
	wind.autoplay = true
	add_child(wind)


func _exit_tree() -> void:
	if not enabled:
		return
	EventBus.unsubscribe(&"weapon.fired", _on_fired)
	EventBus.unsubscribe(&"explosion", _on_explosion)
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)
	EventBus.unsubscribe(&"inventory.changed", _on_inventory_changed)


## Which shot sound a weapon makes: a suppressor on its build quiets it, a semi-auto gun
## is a pistol. Reads the weapon by duck typing so this module needs no other.
static func shot_sound(weapon: Object) -> String:
	if weapon == null:
		return "rifle"
	var build: Variant = weapon.get_meta(&"build", {}) if weapon.has_meta(&"build") else {}
	if build is Dictionary:
		for slot: Variant in build:
			if "supp" in str((build as Dictionary)[slot]):
				return "suppressed"
	if weapon.get(&"semi_auto") == true:
		return "pistol"
	return "rifle"


func _on_fired(p: Dictionary) -> void:
	var from: Vector3 = p.get("from", Vector3.ZERO)
	var to: Vector3 = p.get("to", from)
	var sound := shot_sound(p.get("weapon"))
	play_at(sound, from, float(config.get("shot_range", 300.0)))
	if float(p.get("damage", 0.0)) > 0.0 and p.get("holder") == _local:
		play_flat("hit")
	elif p.get("target") == null and from.distance_to(to) < float(config.get("shot_range", 300.0)) - 1.0:
		play_at("impact", to, 60.0)


func _on_explosion(p: Dictionary) -> void:
	play_at("explosion", p.get("position", Vector3.ZERO), 400.0)


func _on_player_spawned(p: Dictionary) -> void:
	if p.get("local", false):
		_local = p.get("player")


func _on_inventory_changed(_p: Dictionary) -> void:
	var inv := get_tree().get_first_node_in_group(&"inventory_api")
	if inv == null or _local == null:
		return
	var grid: Object = inv.call(&"grid_of", int(_local.get_meta(&"peer_id", 1)))
	if grid == null:
		return
	var count: int = (grid.call(&"items") as Array).size()
	# More items than before: something was picked up or searched out of a crate.
	if _last_items >= 0 and count > _last_items:
		play_flat("pickup")
	_last_items = count


func _process(delta: float) -> void:
	if not enabled:
		return
	_footsteps(delta)
	_own_player()


## Everyone walking makes steps, a footfall every `step_length` metres on the ground.
func _footsteps(delta: float) -> void:
	var step := float(config.get("step_length", 2.0))
	for group: StringName in [&"players", &"enemies"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as CharacterBody3D
			if body == null or body.get_meta(&"dead", false) or not body.is_visible_in_tree():
				continue
			var flat := Vector2(body.velocity.x, body.velocity.z).length()
			if flat < 1.0 or absf(body.velocity.y) > 2.0:
				continue
			var walked := float(_strides.get(body, 0.0)) + flat * delta
			if walked >= step:
				walked -= step
				play_at("footstep", body.global_position, float(config.get("footstep_range", 28.0)), randf_range(0.85, 1.15))
			_strides[body] = walked


## Your own player: a thump when hurt, clicks when a reload starts.
func _own_player() -> void:
	if _local == null or not is_instance_valid(_local):
		return
	var health := _local.get_node_or_null("Health")
	if health != null:
		var now := float(health.get(&"health"))
		if _last_health >= 0.0 and now < _last_health - 0.5:
			play_flat("hurt")
		_last_health = now
	var reloading := false
	for w: Node in get_tree().get_nodes_in_group(&"held_weapons"):
		if w.get(&"holder") == _local and w.get(&"active") != false and w.has_method(&"is_reloading"):
			reloading = bool(w.call(&"is_reloading"))
	if reloading and not _was_reloading:
		play_flat("reload")
	_was_reloading = reloading


## A sound at a place in the world, fading with distance.
func play_at(sound: String, at: Vector3, max_distance: float, pitch: float = 1.0) -> AudioStreamPlayer3D:
	var stream := SoundBank.get_sound(sound)
	if stream == null or not _room():
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = _volume(sound)
	player.max_distance = max_distance
	player.unit_size = 6.0
	player.pitch_scale = pitch
	player.finished.connect(player.queue_free)
	add_child(player)
	player.global_position = at
	player.play()
	_voices.append(player)
	return player


## A sound with no place: feedback for this player only.
func play_flat(sound: String) -> AudioStreamPlayer:
	var stream := SoundBank.get_sound(sound)
	if stream == null or not _room():
		return null
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = _volume(sound)
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()
	_voices.append(player)
	return player


## Too many sounds at once (a firefight) and the oldest give way.
func _room() -> bool:
	_voices = _voices.filter(func(v: Node) -> bool: return is_instance_valid(v) and not v.is_queued_for_deletion())
	while _voices.size() >= int(config.get("max_voices", 48)):
		var oldest: Node = _voices.pop_front()
		oldest.queue_free()
	return true


func _volume(sound: String) -> float:
	return float((config.get("volume_db", {}) as Dictionary).get(sound, 0.0))

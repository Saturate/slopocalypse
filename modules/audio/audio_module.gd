extends Node
## Client only: plays the game's sounds from events it hears on the bus, positioned in the
## world. Shots (rifle, pistol, suppressed) at the shooter, impacts where bullets land, a
## tick when your own shot hits, explosions, everyone's footsteps, and for your own player
## reload clicks, a pickup blip, a thump when hurt, plus quiet wind, birds by day and crickets at night.
## Things that break say what they are made of (`missions.surface_hit`, `surface_broke`,
## `surface_landed`, `{position, material}`): a knock on wood, a ping off metal, glass
## shattering, masonry crumbling, a rumble when a building part lands. Never changes game
## state. Sounds come from SoundBank; volumes are in data/audio.json.

const CONFIG := "res://modules/audio/data/audio.json"
## Quiet enough to count as off for a looping player that keeps running.
const SILENT_DB := -60.0

## Off on a headless server; tests switch it on.
var enabled := DisplayServer.get_name() != "headless"
var config: Dictionary = {}

var _voices: Array[Node] = []
var _strides: Dictionary = {}
var _local: Node3D
var _last_health := -1.0
var _was_reloading := false
var _last_items := -1
## 1 by day, 0 at night, in between at dawn and dusk; from the day and night cycle, full
## day when there is none.
var _daylight := 1.0
var _crickets: AudioStreamPlayer
var _next_bird := 0.0


func _ready() -> void:
	if not enabled:
		return
	var data: Variant = Data.load_json(CONFIG)
	config = data if data is Dictionary else {}
	EventBus.subscribe(&"weapon.fired", _on_fired)
	EventBus.subscribe(&"explosion", _on_explosion)
	EventBus.subscribe(&"drone.diving", _on_drone_diving)
	EventBus.subscribe(&"drone.spawned", _on_drone_spawned)
	EventBus.subscribe(&"drone.mood", _on_drone_mood)
	EventBus.subscribe(&"player.spawned", _on_player_spawned)
	EventBus.subscribe(&"inventory.changed", _on_inventory_changed)
	EventBus.subscribe(&"daytime.hour", _on_hour)
	EventBus.subscribe(&"missions.surface_hit", _on_surface_hit)
	EventBus.subscribe(&"missions.surface_broke", _on_surface_broke)
	EventBus.subscribe(&"missions.surface_landed", _on_surface_landed)
	var wind := AudioStreamPlayer.new()
	wind.name = "Wind"
	wind.stream = SoundBank.get_sound("wind")
	wind.volume_db = _volume("wind")
	wind.autoplay = true
	add_child(wind)
	_crickets = AudioStreamPlayer.new()
	_crickets.name = "Crickets"
	_crickets.stream = SoundBank.get_sound("crickets")
	_crickets.volume_db = SILENT_DB
	_crickets.autoplay = true
	add_child(_crickets)
	_next_bird = _bird_wait()


func _exit_tree() -> void:
	if not enabled:
		return
	EventBus.unsubscribe(&"weapon.fired", _on_fired)
	EventBus.unsubscribe(&"explosion", _on_explosion)
	EventBus.unsubscribe(&"drone.diving", _on_drone_diving)
	EventBus.unsubscribe(&"drone.spawned", _on_drone_spawned)
	EventBus.unsubscribe(&"drone.mood", _on_drone_mood)
	EventBus.unsubscribe(&"player.spawned", _on_player_spawned)
	EventBus.unsubscribe(&"inventory.changed", _on_inventory_changed)
	EventBus.unsubscribe(&"daytime.hour", _on_hour)
	EventBus.unsubscribe(&"missions.surface_hit", _on_surface_hit)
	EventBus.unsubscribe(&"missions.surface_broke", _on_surface_broke)
	EventBus.unsubscribe(&"missions.surface_landed", _on_surface_landed)


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
	elif p.get("target") == null and from.distance_to(to) < float(config.get("shot_range", 300.0)) - 1.0 and not _has_surface_sounds(p.get("collider")):
		play_at("impact", to, 60.0)


## Something that sends its own surface sounds (a building): the plain impact stays quiet.
static func _has_surface_sounds(collider: Variant) -> bool:
	return collider is Object and is_instance_valid(collider) and (collider as Object).has_meta(&"surface_sounds")


## The sound family of a voxel material (`surface_families` in the data), or "" for none.
func surface_family(material: String) -> String:
	return str((config.get("surface_families", {}) as Dictionary).get(material, ""))


func _on_surface_hit(p: Dictionary) -> void:
	var family := surface_family(str(p.get("material", "")))
	play_at("hit_" + family if not family.is_empty() else "impact", p.get("position", Vector3.ZERO), float(config.get("surface_hit_range", 60.0)), randf_range(0.92, 1.08))


## A batch of pieces of one material breaking: louder for more of them.
func _on_surface_broke(p: Dictionary) -> void:
	var family := surface_family(str(p.get("material", "")))
	if family.is_empty():
		return
	var voice := play_at("break_" + family, p.get("position", Vector3.ZERO), float(config.get("surface_break_range", 160.0)), randf_range(0.9, 1.1))
	if voice != null:
		voice.volume_db += minf(6.0, 2.0 * log(maxf(1.0, float(p.get("count", 1)))) / log(2.0))


func _on_surface_landed(p: Dictionary) -> void:
	play_at("collapse", p.get("position", Vector3.ZERO), float(config.get("surface_break_range", 160.0)) * 1.5, randf_range(0.9, 1.05))


func _on_explosion(p: Dictionary) -> void:
	play_at("explosion", p.get("position", Vector3.ZERO), 400.0)


## The dive whine rides along with the drone, so it grows louder as it comes.
func _on_drone_diving(p: Dictionary) -> void:
	var drone := p.get("drone") as Node3D
	if drone == null:
		return
	var sound := play_at("dive", drone.global_position, 200.0)
	if sound != null:
		sound.reparent(drone)


## Every drone hums wherever it flies, so you hear one before you see it.
func _on_drone_spawned(p: Dictionary) -> void:
	var drone := p.get("drone") as Node3D
	if drone == null or drone.get_node_or_null("Hum") != null:
		return
	var hum := AudioStreamPlayer3D.new()
	hum.name = "Hum"
	hum.stream = SoundBank.get_sound("rotor")
	hum.volume_db = _volume("rotor")
	hum.max_distance = float(config.get("rotor_range", 140.0))
	hum.unit_size = 6.0
	hum.autoplay = true
	drone.add_child(hum)


## Angry drones whine higher and louder.
func _on_drone_mood(p: Dictionary) -> void:
	var drone := p.get("drone") as Node3D
	var hum := drone.get_node_or_null("Hum") as AudioStreamPlayer3D if drone != null else null
	if hum == null:
		return
	var angry := bool(p.get("angry", false))
	hum.pitch_scale = float(config.get("rotor_angry_pitch", 1.3)) if angry else 1.0
	hum.volume_db = _volume("rotor") + (float(config.get("rotor_angry_db", 5.0)) if angry else 0.0)


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
	var count: int = (grid.call(&"all_items") as Array).size()
	# More items than before: something was picked up or searched out of a crate.
	if _last_items >= 0 and count > _last_items:
		play_flat("pickup")
	_last_items = count


func _process(delta: float) -> void:
	var prof := Prof.start()
	_process_tick(delta)
	Prof.stop(&"audio/module:frame", prof)


func _process_tick(delta: float) -> void:
	if not enabled:
		return
	_footsteps(delta)
	_own_player()
	_ambience(delta)


func _on_hour(p: Dictionary) -> void:
	_daylight = clampf(float(p.get("daylight", 1.0)), 0.0, 1.0)


## Birds by day, crickets at night, under the wind. A bird sings now and then somewhere
## around you, a different song and pitch each time; fewer as the light goes.
func _ambience(delta: float) -> void:
	var cricket_db := _volume("crickets") + linear_to_db(maxf(1.0 - _daylight, 0.001))
	_crickets.volume_db = maxf(cricket_db, SILENT_DB)
	_next_bird -= delta
	if _next_bird > 0.0:
		return
	_next_bird = _bird_wait()
	var listener := _listener()
	if listener == null or randf() > _daylight:
		return
	var birds := config.get("birds", {}) as Dictionary
	var angle := randf() * TAU
	var distance := randf_range(float(birds.get("distance_min", 12.0)), float(birds.get("distance_max", 45.0)))
	var at := listener.global_position + Vector3(cos(angle) * distance, randf_range(3.0, 10.0), sin(angle) * distance)
	var song := "bird%d" % randi_range(0, SoundBank.BIRD_VARIANTS - 1)
	var voice := play_at(song, at, distance * 3.0, randf_range(0.85, 1.2))
	if voice != null:
		voice.volume_db = _volume("bird")


func _bird_wait() -> float:
	var birds := config.get("birds", {}) as Dictionary
	return randf_range(float(birds.get("min_seconds", 2.0)), float(birds.get("max_seconds", 7.0)))


## Where you hear from: the current camera.
func _listener() -> Node3D:
	return get_viewport().get_camera_3d()


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
	# Freed voices are no longer Nodes, so the lambda takes a Variant, and filter() returns
	# an untyped Array that has to go back in through assign().
	_voices.assign(_voices.filter(func(v: Variant) -> bool: return is_instance_valid(v) and not (v as Node).is_queued_for_deletion()))
	while _voices.size() >= int(config.get("max_voices", 48)):
		var oldest: Node = _voices.pop_front()
		oldest.queue_free()
	return true


func _volume(sound: String) -> float:
	return float((config.get("volume_db", {}) as Dictionary).get(sound, 0.0))

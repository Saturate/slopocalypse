extends Node
## Day and night. The server owns the hour and tells clients when they join and every few
## seconds after; clients run the same clock in between, so the sun moves smoothly and
## everyone sees the same time.

var _clock: DayClock
var _lighting: DayLighting
var _since_sync := 0.0
var _since_update := 0.0


func clock() -> DayClock:
	return _clock


func _ready() -> void:
	_clock = DayClock.from_data()
	if _clock == null:
		set_process(false)
		return
	Net.peer_joined.connect(_on_peer_joined)
	EventBus.subscribe(&"world.ready", _on_world_ready)
	EventBus.subscribe(&"admin.set_hour", _on_admin_set_hour)
	if DisplayServer.get_name() != "headless":
		_lighting = DayLighting.new()
		_lighting.name = "Lighting"
		add_child(_lighting)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"world.ready", _on_world_ready)
	EventBus.unsubscribe(&"admin.set_hour", _on_admin_set_hour)
	if Net.peer_joined.is_connected(_on_peer_joined):
		Net.peer_joined.disconnect(_on_peer_joined)


func _on_world_ready(_p: Dictionary) -> void:
	if _lighting == null:
		return
	var env := get_tree().get_first_node_in_group(&"world_environment") as WorldEnvironment
	_lighting.attach(get_tree().get_first_node_in_group(&"sun") as DirectionalLight3D, env.environment if env != null else null)
	_lighting.apply(_clock)


func _process(delta: float) -> void:
	var prof := Prof.start()
	_process_tick(delta)
	Prof.stop(&"daytime/module:frame", prof)


func _process_tick(delta: float) -> void:
	_clock.advance(delta)
	# A client still connecting has no peer yet, and asking it whether it is the server errors.
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_since_sync += delta
		if _since_sync >= float(_clock.config["sync_seconds"]):
			_since_sync = 0.0
			_send_hour()
	if _lighting != null:
		_since_update += delta
		if _since_update >= float(_clock.config["update_seconds"]):
			_since_update = 0.0
			_lighting.apply(_clock)
			# Local only: sound and anything else on this machine that follows the light.
			EventBus.publish(&"daytime.hour", {"hour": _clock.hour, "daylight": _clock.daylight()})


## Server: jump to `hour` everywhere at once.
func server_set_hour(hour: float) -> void:
	if not multiplayer.is_server():
		return
	_clock.set_hour(hour)
	Log.info(&"daytime", "time set to %05.2f" % _clock.hour)
	_send_hour()
	if _lighting != null:
		_lighting.apply(_clock)


func _send_hour() -> void:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer or multiplayer.get_peers().is_empty():
		return
	_receive_hour.rpc(_clock.hour)


func _on_peer_joined(peer: int) -> void:
	if multiplayer.is_server():
		_receive_hour.rpc_id(peer, _clock.hour)


@rpc("authority", "call_remote", "reliable")
func _receive_hour(hour: float) -> void:
	_clock.set_hour(hour)
	if _lighting != null:
		_lighting.apply(_clock)


func _on_admin_set_hour(p: Dictionary) -> void:
	server_set_hour(float(p.get("hour", 12.0)))

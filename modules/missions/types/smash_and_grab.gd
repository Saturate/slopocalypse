extends MissionType
## Smash & Grab: the drive waits in a crate inside one of the zone's buildings. The clock
## starts when someone walks into the zone, and from then strike drones come in waves and
## dive into the zone, more as time runs out and nonstop once it has. Riding home with the
## drive in anyone's gear hands it in and completes the job.

var _crate: Node3D
## Server: seconds since the clock started, the next wave, and the countdown to the next
## overtime wave once time is up.
var _elapsed := 0.0
var _next_wave := 0
var _overtime_in := 0.0


func server_open() -> void:
	var buildings: Array = missions.call(&"building_nodes")
	var zone: Vector3 = missions.get(&"zone")
	var at: Vector3 = (buildings[0] as MissionBuilding).inside(0.85, 0.0) if not buildings.is_empty() else zone
	_crate = missions.call(&"spawn_crate", at, [_item()])
	missions.call(&"fill_buildings_with_loot", [0])
	status = {"time_left": -1.0, "delivered": false, "drive": _crate.global_position if _crate != null else at}
	changed()


func _item() -> String:
	return str(mission.get("objective_item", "usb_drive"))


func time_left() -> float:
	return float(status.get("time_left", -1.0))


func server_tick(delta: float) -> void:
	if time_left() < 0.0:
		if not (missions.call(&"riders_in_zone") as Array).is_empty():
			status["time_left"] = float(mission.get("time_limit", 180.0))
			EventBus.publish(&"missions.clock_started", {"mission": mission.get("id", ""), "seconds": time_left()})
			changed()
		return
	_step_strikes(delta)


## The clock counts down on every instance after the server starts it.
func client_tick(delta: float) -> void:
	if time_left() > 0.0:
		var was := time_left()
		status["time_left"] = maxf(was - delta, 0.0)
		if multiplayer.is_server() and time_left() <= 0.0:
			EventBus.publish(&"missions.time_up", {"mission": mission.get("id", "")})


## Server: sends the waves that are due and, once time is up, a wave every `overtime_every`
## seconds; never more than `max_flying` at once.
func _step_strikes(delta: float) -> void:
	var strikes: Dictionary = mission.get("strikes", {})
	var waves: Array = strikes.get("waves", [])
	_elapsed += delta
	while _next_wave < waves.size() and _elapsed >= float((waves[_next_wave] as Dictionary).get("at", 0.0)):
		_send_strike(int((waves[_next_wave] as Dictionary).get("drones", 1)))
		_next_wave += 1
	if time_left() > 0.0:
		return
	_overtime_in -= delta
	if _overtime_in <= 0.0:
		_overtime_in = float(strikes.get("overtime_every", 10.0))
		_send_strike(int(strikes.get("overtime_drones", 3)))


func _send_strike(count: int) -> void:
	var drones := get_tree().get_first_node_in_group(&"drones_api")
	if drones == null:
		return
	var strikes: Dictionary = mission.get("strikes", {})
	var room := int(strikes.get("max_flying", 10)) - int(drones.call(&"strike_count"))
	var rng: RandomNumberGenerator = missions.get(&"rng")
	var buildings: Array = missions.get(&"buildings")
	for i in mini(count, room):
		var at: Vector3 = missions.call(&"random_spot", float(strikes.get("spread", 0.8)))
		# Some go for the buildings: their roofs.
		if not buildings.is_empty() and rng.randf() < float(strikes.get("building_share", 0.5)):
			var b: Dictionary = buildings[rng.randi_range(0, buildings.size() - 1)]
			at = (b["position"] as Vector3) + Vector3.UP * float(b["wall_height"])
		drones.call(&"server_spawn_strike", at)
	EventBus.publish(&"missions.strike", {"mission": mission.get("id", ""), "drones": mini(count, room)})


func server_done(riders: Array) -> bool:
	var inventory := get_tree().get_first_node_in_group(&"inventory_api")
	if inventory == null or bool(status.get("delivered", false)):
		return false
	for peer: int in riders:
		if int(inventory.call(&"count", peer, _item())) > 0:
			inventory.call(&"server_take", peer, _item())
			status["delivered"] = true
			changed()
			return true
	return false


func server_close() -> void:
	var drones := get_tree().get_first_node_in_group(&"drones_api")
	if drones != null:
		drones.call(&"server_clear_strikes")


func hud_lines(player: Node3D) -> Array[String]:
	var lines: Array[String] = []
	var left := time_left()
	if bool(status.get("delivered", false)):
		lines.append("Drive delivered")
	elif left < 0.0:
		lines.append("Reach the zone")
	elif left > 0.0:
		lines.append("Strike in %d:%02d" % [int(left) / 60, int(left) % 60])
	else:
		lines.append("STRIKE INCOMING")
	var drive: Vector3 = status.get("drive", Vector3.ZERO)
	if not bool(status.get("delivered", false)):
		lines.append("Drive %d m" % int(player.global_position.distance_to(drive)))
	return lines


func markers() -> Array:
	if bool(status.get("delivered", false)) or not status.has("drive"):
		return []
	return [{"at": (status["drive"] as Vector3) + Vector3.UP * 2.2, "text": "DRIVE"}]

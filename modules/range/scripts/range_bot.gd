extends Node
## `--bot=range` on the test range: works through the row of buildings from where it stands,
## firing at each one's front at a few heights, then sticking a charge on it and setting it
## off, and again from the first. A fixed, repeatable load for `tools/bench.ts range-destroy`.
## Drives the player through the same intent path a person does: on a client it sends its
## aim and buttons to the server.

var player: PlayerController
## `bot` from the range data: fire_seconds, aim_heights, charge_wait_seconds, settle_seconds.
var settings: Dictionary = {}

var _ticks := 0
var _target := 0
var _phase_ticks := 0
var _phase := "fire"


func _physics_process(delta: float) -> void:
	var prof := Prof.start()
	_physics_tick(delta)
	Prof.stop(&"range/bot:physics", prof)


func _physics_tick(_delta: float) -> void:
	var missions := get_tree().get_first_node_in_group(&"missions_api")
	if player == null or missions == null:
		return
	var buildings: Array = missions.call(&"building_nodes")
	if buildings.is_empty():
		return
	_ticks += 1
	_phase_ticks += 1
	var b := buildings[_target % buildings.size()] as Node3D
	var heights: Array = settings.get("aim_heights", [1.2])
	var fire_ticks := int(float(settings.get("fire_seconds", 3.0)) * 60.0)
	var fire := false
	var action := &""
	var aim_height := float(heights[0])
	match _phase:
		"fire":
			# Sweep the heights across the burst, firing in short bursts.
			aim_height = float(heights[mini(heights.size() - 1, int(float(_phase_ticks) / float(maxi(1, fire_ticks)) * heights.size()))])
			fire = (_phase_ticks % 20) < 8
			if _phase_ticks >= fire_ticks:
				_next("charge")
		"charge":
			aim_height = 0.6
			if _phase_ticks == 10:
				action = &"throw"
			if _phase_ticks >= int(float(settings.get("charge_wait_seconds", 1.0)) * 60.0):
				action = &"detonate"
				_next("settle")
		"settle":
			if _phase_ticks >= int(float(settings.get("settle_seconds", 2.0)) * 60.0):
				_target += 1
				_next("fire")
	var spec: Dictionary = b.get(&"spec")
	var front := b.global_transform * Vector3(0.0, 0.0, -float(spec.get("depth", 4.0)) / 2.0)
	_aim(front + Vector3.UP * aim_height, fire, action)


func _next(phase: String) -> void:
	_phase = phase
	_phase_ticks = 0


func _aim(at: Vector3, fire: bool, action: StringName) -> void:
	var intent := player.intent()
	var eye := player.global_position + Vector3.UP * 1.6
	var dir := (at - eye).normalized()
	var yaw := atan2(-dir.x, -dir.z)
	var pitch := asin(clampf(dir.y, -1.0, 1.0))
	intent.remote_look = true
	intent.look_yaw = yaw
	intent.look_pitch = pitch
	intent.fire = fire
	if multiplayer.is_server():
		if not action.is_empty():
			intent.set(action, true)
	else:
		intent.submit.rpc_id(1, Vector2.ZERO, yaw, pitch, false, false, fire, false)
		if not action.is_empty():
			intent.submit_action.rpc_id(1, action)

extends Node3D
## Capture setup: four soldiers stand in a row and die one after another (#387): the first
## to a blast behind it, the others to heavy shots on a forearm, a thigh and a shin. Each
## ragdoll falls missing what was hit, a red stump where it was, and the piece flies off,
## bleeding, and lands near the body.
##
## With GORE_PROBE set to a file path, every frame's time and shader pipeline compiles from
## just before the first death on are appended there: what the first sever costs.

const WORLD := "res://modules/world/scenes/world.tscn"
const PLAYER := "res://modules/player/scenes/player.tscn"
## [x on the line, physics tick it dies on, how: "blast" or the bone a shot hits].
const VICTIMS := [
	[-3.6, 50, "blast"],
	[-1.2, 70, "LowerArm_R"],
	[1.2, 110, "UpperLeg_L"],
	[3.6, 150, "LowerLeg_R"],
]
const LANDED := 45
const SHOT_DAMAGE := 100.0

var _soldiers: Array[PlayerController] = []
var _camera := Camera3D.new()
var _ticks := 0
var _probe := OS.get_environment("GORE_PROBE")
var _last_usec := 0
var _compiled := 0
var _limbs: LimbSevering


func _ready() -> void:
	await VoxelWorld.add_and_wait(self, WORLD)
	Corpse.enabled = true
	var effects := BloodEffects.new()
	add_child(effects)
	_limbs = LimbSevering.new()
	_limbs.blood = effects
	add_child(_limbs)
	for v: Array in VICTIMS:
		var soldier: PlayerController = (load(PLAYER) as PackedScene).instantiate()
		soldier.add_to_group(&"enemies")
		add_child(soldier)
		soldier.global_position = Vector3(float(v[0]), 0.5, 0.0)
		var animator := PlayerBodyAnimator.new()
		animator.name = "BodyAnimator"
		animator.player = soldier
		soldier.add_child(animator)
		_soldiers.append(soldier)
	add_child(_camera)
	_camera.current = true
	# Close and from above, with a lamp: the road here runs under an overpass and is dark.
	_camera.global_position = Vector3(0.0, 3.6, 3.8)
	_camera.look_at(Vector3(0.0, 0.0, -0.6))
	var lamp := OmniLight3D.new()
	lamp.omni_range = 12.0
	lamp.light_energy = 2.5
	add_child(lamp)
	lamp.global_position = Vector3(0.0, 4.0, 1.0)


func _process(_delta: float) -> void:
	if _probe.is_empty():
		return
	var now := Time.get_ticks_usec()
	var compiles := 0
	for kind in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		compiles += RenderingServer.get_rendering_info(kind)
	if _last_usec > 0:
		_note("tick %d frame_ms %.2f compiles %d" % [_ticks, float(now - _last_usec) / 1000.0, compiles - _compiled])
	_last_usec = now
	_compiled = compiles


func _physics_process(_delta: float) -> void:
	if _soldiers.is_empty():
		return
	_ticks += 1
	if _ticks == LANDED:
		for soldier in _soldiers:
			soldier.set_physics_process(false)
	for i in VICTIMS.size():
		var v: Array = VICTIMS[i]
		if _ticks != int(v[1]):
			continue
		var soldier := _soldiers[i]
		var how := String(v[2])
		# As on a client: the death and its ragdoll first, then the blow that caused it.
		var push := Vector3(0.0, float(Corpse.config()["push_up"]), -float(Corpse.config()["push"]))
		var skeleton := soldier.get_node("Body/Skeleton") as Skeleton3D
		var target := Vector3.ZERO
		if how != "blast":
			var bone := skeleton.find_bone(how)
			var child := skeleton.get_bone_children(bone)
			var a := (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin
			var b := (skeleton.global_transform * skeleton.get_bone_global_pose(child[0])).origin if child.size() > 0 else a + Vector3.DOWN * 0.3
			target = a.lerp(b, 0.5)
		var t0 := Time.get_ticks_usec()
		var corpse := Corpse.from_body(soldier, push)
		(soldier.get_node("Body") as Node3D).visible = false
		(soldier.get_node("Shape") as CollisionShape3D).set_deferred(&"disabled", true)
		var t1 := Time.get_ticks_usec()
		if how == "blast":
			EventBus.publish(&"explosion", {"position": soldier.global_position + Vector3(-0.6, 0.2, -0.6), "radius": 3.0, "source": null})
		else:
			EventBus.publish(&"weapon.fired", {"from": target + Vector3(0.0, 0.3, 6.0), "to": target, "target": soldier, "collider": soldier, "damage": SHOT_DAMAGE})
		var t2 := Time.get_ticks_usec()
		# Measured here rather than next frame, so its cost stands apart from the ragdoll's.
		_limbs.resolve(true)
		var t3 := Time.get_ticks_usec()
		var gone: Array[String] = []
		for limb: String in LimbRules.LIMBS:
			var bone := corpse.skeleton.find_bone(LimbRules.root_bone(limb))
			if corpse.skeleton.get_bone_pose_scale(bone).x < 0.01:
				gone.append(limb)
		_note("death %s: ragdoll %.2f ms, events %.2f ms, sever %.2f ms, pieces %d, gone %s" % [how, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, _limbs.pieces().size(), gone])


func _note(line: String) -> void:
	if _probe.is_empty():
		return
	var file := FileAccess.open(_probe, FileAccess.READ_WRITE if FileAccess.file_exists(_probe) else FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(line)

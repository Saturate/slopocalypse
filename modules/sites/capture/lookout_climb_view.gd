extends "res://modules/sites/capture/site_view.gd"
## Capture setup: climbing the first lookout tower's ladder in first person. It walks in with
## the gun at the hip, climbs with the trigger and the sights held (neither works on a
## ladder, so the gun stays lowered), looks down the ladder partway up, and climbs on.

const PLAYER := "res://modules/player/scenes/player.tscn"
## Metres in front of the ladder's reach the climber starts.
const START_BACK := 3.0

var _climber: PlayerController
var _ticks := 0


func _init() -> void:
	kind = "lookout"
	from_distance = 20.0
	to_distance = 12.0
	look_up = 4.5


func _ready() -> void:
	await super()
	var tower := _tower()
	if tower == null:
		push_error("no lookout tower on the first lookout site")
		return
	var climb := VoxLookoutTower.ladder_box(tower.params)
	var into := (tower.global_basis * VoxLookoutTower.ladder_into()).normalized()
	var foot := tower.global_transform * Vector3(0.0, 0.0, climb.position.z - START_BACK)
	foot.y = _terrain.surface_height(foot.x, foot.z) + 0.1
	_climber = (load(PLAYER) as PackedScene).instantiate()
	add_child(_climber)
	_climber.global_position = foot
	_climber.rotation.y = atan2(-into.x, -into.z)
	var animator := PlayerBodyAnimator.new()
	animator.player = _climber
	_climber.add_child(animator)
	PlayerBody.weapon_socket(_climber).add_child(GunAssembly.build_model(GunAssembly.build(GunAssembly.default_build())))
	PlayerBody.first_person(_climber.get_node("Body"))
	var eye := _climber.get_node("Head/Camera") as Camera3D
	eye.current = true
	eye.add_child(_terrain.make_viewer())
	_light_from_behind(find_child("Sun", true, false) as DirectionalLight3D, foot + into * 4.0)


func _tower() -> VoxPiece:
	var centre: Vector3 = _site["centre"]
	var best: VoxPiece = null
	for node in find_children("*", "Node3D", true, false):
		var piece := node as VoxPiece
		if piece == null or piece.generator != "VoxLookoutTower":
			continue
		if best == null or piece.global_position.distance_to(centre) < best.global_position.distance_to(centre):
			best = piece
	return best


func _physics_process(_delta: float) -> void:
	if _climber == null:
		return
	_ticks += 1
	var intent := _climber.intent()
	intent.move = Vector2(0.0, 1.0) if _ticks > 20 and not (_ticks > 160 and _ticks < 260) else Vector2.ZERO
	# Trigger and sights held from the foot of the ladder all the way up.
	intent.fire = _ticks > 90
	intent.aim = _ticks > 90
	# Look down the ladder while holding on, then back up.
	var pitch := -1.0 if _ticks > 170 and _ticks < 240 else 0.0
	intent.remote_look = true
	intent.look_yaw = _climber.rotation.y
	intent.look_pitch = move_toward(float(_climber.get_node("Head").rotation.x), pitch, 0.04)


func _place(share: float) -> void:
	if _climber == null:
		super(share)

extends "res://modules/sites/capture/site_view.gd"
## Capture setup: someone climbing the first lookout tower's ladder, seen from the side the way
## another player sees them. The climber is simulated as on the server and hidden; what the
## camera shows is a copy held still that gets only what the server sends (position, turn,
## velocity, the climbing flag), as on another client. It walks in, climbs, stops a moment
## holding on, and climbs on.

const PLAYER := "res://modules/player/scenes/player.tscn"
## Metres in front of the ladder's reach the climber starts.
const START_BACK := 0.5
## The observer's distance to the side of the ladder and back from it, metres.
const SIDE := 2.4
const BACK := 1.4

var _climber: PlayerController
var _copy: PlayerController
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
	(_climber.get_node("Body") as Node3D).visible = false
	_copy = (load(PLAYER) as PackedScene).instantiate()
	PlayerController.hold_still(_copy)
	_copy.collision_layer = 0
	add_child(_copy)
	var animator := PlayerBodyAnimator.new()
	animator.player = _copy
	_copy.add_child(animator)
	PlayerBody.weapon_socket(_copy).add_child(GunAssembly.build_model(GunAssembly.build(GunAssembly.default_build())))
	_mirror()
	_light_from_behind(find_child("Sun", true, false) as DirectionalLight3D, foot)


func _physics_process(_delta: float) -> void:
	if _climber == null:
		return
	_ticks += 1
	# Walk in, climb, hold on for a moment, climb on.
	var moving := _ticks > 6 and not (_ticks > 110 and _ticks < 140)
	_climber.intent().move = Vector2(0.0, 1.0) if moving else Vector2.ZERO
	_mirror()


## What the server sends another client about the climber.
func _mirror() -> void:
	_copy.global_position = _climber.global_position
	_copy.rotation.y = _climber.rotation.y
	_copy.velocity = _climber.velocity
	_copy.climbing = _climber.climbing
	_copy.mode = _climber.mode


func _place(share: float) -> void:
	if _copy == null:
		super(share)
		return
	var into := _copy.ladder_into()
	if into == Vector3.ZERO:
		into = -_copy.global_basis.z
	var side := into.cross(Vector3.UP).normalized()
	var at := _copy.global_position
	_camera.global_position = at + side * SIDE - into * BACK + Vector3.UP * 1.0
	_camera.look_at(at + Vector3.UP * 0.9)

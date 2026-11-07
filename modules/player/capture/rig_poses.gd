extends Node3D
## Capture setup: the third-person body alone on flat ground, seen from the side, stepping
## through every animation state by setting the blend parameters directly. Deterministic,
## so a reviewer judges the rig and its clips, not gameplay movement.

const BODY := "res://modules/player/scenes/player_body.tscn"
const RIFLE_MESH := "res://modules/weapons/scripts/rifle_mesh.gd"
## Frames each state is held, at the capture's fixed 30 fps.
const HOLD := 30
## [label, loco speed, crouch, air, slide, aim pitch in degrees]
const STATES := [
	["idle", 0.0, 0.0, 0.0, 0.0, 0.0],
	["walk", 4.5, 0.0, 0.0, 0.0, 0.0],
	["run", 7.0, 0.0, 0.0, 0.0, 0.0],
	["aim up", 0.0, 0.0, 0.0, 0.0, 40.0],
	["aim down", 0.0, 0.0, 0.0, 0.0, -35.0],
	["crouch", 0.0, 1.0, 0.0, 0.0, 0.0],
	["crouch walk", 2.2, 1.0, 0.0, 0.0, 0.0],
	["slide", 7.0, 0.0, 0.0, 1.0, 0.0],
	["fall", 0.0, 0.0, 1.0, 0.0, 0.0],
]

var _tree: AnimationTree
var _aim: Node
var _label := Label3D.new()
var _ticks := 0


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = ProceduralSkyMaterial.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mesh.mesh = plane
	add_child(floor_mesh)

	var body: Node3D = (load(BODY) as PackedScene).instantiate()
	add_child(body)
	_tree = body.get_node("AnimationTree")
	_aim = body.get_node("Skeleton/Aim")
	var held := MeshInstance3D.new()
	held.mesh = (load(RIFLE_MESH) as GDScript).call(&"rifle")
	body.get_node("Skeleton/WeaponAttachment/WeaponSocket").add_child(held)

	_label.position = Vector3(0, 2.2, 0)
	_label.font_size = 64
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)
	var camera := Camera3D.new()
	camera.fov = 40.0
	add_child(camera)
	# Side view: the body faces -Z, so look at it from +X.
	camera.position = Vector3(5.0, 1.1, 0.0)
	camera.look_at(Vector3(0, 0.9, 0))
	camera.current = true


func _process(_delta: float) -> void:
	# The first hold is lead-in: the capture's first frames are often not rendered yet.
	var state: Array = STATES[clampi(_ticks / HOLD - 1, 0, STATES.size() - 1)]
	_ticks += 1
	_label.text = state[0]
	_tree.set(&"parameters/loco/blend_position", state[1])
	_tree.set(&"parameters/crouch_loco/blend_position", state[1])
	_tree.set(&"parameters/crouch/blend_amount", state[2])
	_tree.set(&"parameters/air/blend_amount", state[3])
	_tree.set(&"parameters/slide/blend_amount", state[4])
	_aim.set(&"pitch", deg_to_rad(state[5]))

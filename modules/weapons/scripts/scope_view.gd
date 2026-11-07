class_name ScopeView
extends Node
## Client only, for the local player's scoped gun: renders the world magnified into a lens
## on the scope's eyepiece, picture in picture, while the rest of the screen stays at
## normal zoom. The scope camera sits at the objective and looks down the gun, so the
## picture moves with sway and recoil. It only renders while aiming.

const RESOLUTION := 512
## The lens' radius on the eyepiece, metres; matches the eyecup's inner radius.
const LENS_RADIUS := 0.021
## Below this much ADS the lens is dark glass and nothing extra renders.
const ACTIVE_FROM := 0.3
const LENS_SHADER := "res://modules/weapons/shaders/scope_lens.gdshader"

var player: PlayerController
var gun: Node3D

var _viewport: SubViewport
var _camera: Camera3D
var _lens: MeshInstance3D
var _material: ShaderMaterial
var _animator: PlayerBodyAnimator
var _eye: Camera3D


func _ready() -> void:
	_eye = player.get_node("Head/Camera")
	_viewport = SubViewport.new()
	_viewport.name = "ScopeViewport"
	_viewport.size = Vector2i(RESOLUTION, RESOLUTION)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.near = 0.05
	_camera.far = 2000.0
	_camera.cull_mask &= ~RenderLayers.bit(RenderLayers.MAIN_VIEW_ONLY)
	_viewport.add_child(_camera)
	_camera.current = true
	_material = ShaderMaterial.new()
	_material.shader = load(LENS_SHADER)
	_material.set_shader_parameter(&"view", _viewport.get_texture())
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * LENS_RADIUS * 2.0
	_lens = MeshInstance3D.new()
	_lens.name = "ScopeLens"
	_lens.mesh = quad
	_lens.material_override = _material
	_lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A quad faces +Z, back toward the eye, since guns point down -Z.
	gun.get_node("Lens").add_child(_lens)


func _process(_delta: float) -> void:
	if not is_instance_valid(gun):
		queue_free()
		return
	# Looked up late: the player module may add the animator after weapons equip the gun.
	if _animator == null:
		_animator = player.get_node_or_null("BodyAnimator") as PlayerBodyAnimator
	var ads := _animator.ads_amount() if _animator != null else 0.0
	var active := ads > ACTIVE_FROM
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	_material.set_shader_parameter(&"active", clampf((ads - ACTIVE_FROM) / (1.0 - ACTIVE_FROM), 0.0, 1.0))
	if not active:
		return
	if _camera.environment == null:
		_camera.environment = _lens_environment()
	var objective := gun.get_node("Objective") as Node3D
	_camera.global_transform = objective.global_transform.orthonormalized()
	_camera.fov = fov_for(_eye.global_position.distance_to(_lens.global_position), _animator.sight_magnification())


## The world's environment without tone mapping or glow: the picture is drawn unshaded
## into the main view, which tone maps it once; mapping it here too would darken it.
func _lens_environment() -> Environment:
	var world := _viewport.find_world_3d()
	if world == null or world.environment == null:
		return null
	var env := world.environment.duplicate() as Environment
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = false
	return env


## The scope camera's field of view: the angle the lens covers from the eye, divided by
## the magnification, so things through the lens look that many times bigger than beside
## it.
static func fov_for(eye_distance: float, magnification: float) -> float:
	var lens_angle := 2.0 * atan(LENS_RADIUS / maxf(eye_distance, 0.01))
	return clampf(rad_to_deg(lens_angle) / maxf(magnification, 1.0), 0.5, 90.0)

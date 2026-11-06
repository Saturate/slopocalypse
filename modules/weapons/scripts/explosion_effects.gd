class_name ExplosionEffects
extends Node
## Client-only: flash, dust cloud and flying debris for every `explosion` event. Purely
## visual; craters and damage are decided on the server.

const FLASH_SECONDS := 0.12
const DUST_SECONDS := 6.0


func _ready() -> void:
	EventBus.subscribe(&"explosion", _on_explosion)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"explosion", _on_explosion)


func _on_explosion(p: Dictionary) -> void:
	var at: Vector3 = p["position"]
	var radius: float = p["radius"]
	var root := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.75, 0.45)
	flash.light_energy = 12.0
	flash.omni_range = radius * 6.0
	root.add_child(flash)
	flash.global_position = at + Vector3.UP * 0.5
	var tween := flash.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, FLASH_SECONDS)
	tween.tween_callback(flash.queue_free)
	root.add_child(_burst(at, radius, _dust_mesh(), 80, Vector2(1.2, 4.0), DUST_SECONDS, 0.3, Color(0.36, 0.3, 0.24, 0.75)))
	root.add_child(_burst(at, radius, _debris_mesh(), 40, Vector2(6.0, 14.0), 2.0, 9.8, Color(0.42, 0.35, 0.26)))


## One-shot particle burst. Dust drifts slowly upward; debris is thrown out and falls.
func _burst(at: Vector3, radius: float, mesh: Mesh, amount: int, speed: Vector2, lifetime: float, gravity: float, colour: Color) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.amount = amount
	particles.lifetime = lifetime
	particles.draw_pass_1 = mesh
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius * 0.4
	process.direction = Vector3.UP
	process.spread = 70.0
	process.initial_velocity_min = speed.x
	process.initial_velocity_max = speed.y
	process.gravity = Vector3.DOWN * gravity
	process.damping_min = 1.0
	process.damping_max = 2.5
	process.scale_min = 0.6
	process.scale_max = 1.6
	process.color = colour
	# Fade out over the particle's life so clouds thin away rather than vanish.
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	process.angular_velocity_min = -360.0
	process.angular_velocity_max = 360.0
	particles.process_material = process
	particles.emitting = true
	particles.position = at
	particles.finished.connect(particles.queue_free)
	return particles


## Soft billboard puffs: a radial gradient fading to transparent, lit so the cloud picks up
## the sun, and fading out over its lifetime instead of popping.
func _dust_mesh() -> Mesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.2, 2.2)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.9))
	gradient.set_color(1, Color(1, 1, 1, 0.0))
	var soft := GradientTexture2D.new()
	soft.gradient = gradient
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	soft.width = 64
	soft.height = 64
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = soft
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.roughness = 1.0
	quad.material = mat
	return quad


## Chunky lit clods. The particle colour arrives as a vertex colour in sRGB; without the
## flag they rendered as flat near-black squares.
func _debris_mesh() -> Mesh:
	var box := BoxMesh.new()
	box.size = Vector3(0.22, 0.16, 0.2)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	box.material = mat
	return box

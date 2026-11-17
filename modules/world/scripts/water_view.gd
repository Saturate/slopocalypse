class_name WaterView
extends Node3D
## Client: one flat surface per pond at its level, shaded by how much water is under each
## spot (shallow tint at the edge to deep tint `colour_depth` metres down), with what is
## under the surface showing through, wobbled on a 0.25 m grid so it stays blocky like the
## ground. Flooded craters get the same surface over their bowl.
##
## Ripples: the last `MAX_RIPPLES` disturbances (rounds and blasts hitting the water, people
## and cars moving through it) go to the shader as rings that grow at `ripple_speed` and fade
## over `ripple_seconds`, drawn on the same grid. Rounds and blasts also throw a splash.

const SHADER := """
shader_type spatial;
// Drawn after the opaque pass (ALPHA is set), so the screen and depth textures hold the
// ground under it.
render_mode cull_disabled, depth_draw_always;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform vec3 shallow : source_color = vec3(0.32, 0.5, 0.45);
uniform vec3 deep : source_color = vec3(0.05, 0.16, 0.2);
uniform float colour_depth = 3.0;
uniform float cell = 0.25;
// x, z, when it started (`now`'s clock), strength (0: unused).
uniform vec4 ripples[16];
uniform float now;
uniform float ripple_speed = 1.5;
uniform float ripple_seconds = 1.5;
varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 snapped = floor(world.xz / cell);
	float t = floor(TIME * 3.0);
	vec2 wobble = (vec2(hash(snapped + t), hash(snapped.yx - t)) - 0.5) * 0.006;
	vec2 uv = SCREEN_UV + wobble;
	float d = texture(depth_tex, uv).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, d, 1.0);
	view.xyz /= view.w;
	// How much water the eye looks through to reach what is behind the surface here.
	float through = max(length(view.xyz) - length(VERTEX), 0.0);
	if (-view.z < -VERTEX.z) {
		// Something in front of the water: don't refract it in.
		uv = SCREEN_UV;
		through = 0.0;
	}
	float k = clamp(through / colour_depth, 0.0, 1.0);
	vec3 behind = texture(screen, uv).rgb;
	vec3 tint = mix(shallow, deep, k);
	// What is under the water was lit already: it shows through as emission, fading with depth,
	// so it isn't lit twice; the water's own tint takes the light.
	ALBEDO = tint * (0.35 + 0.65 * k);
	EMISSION = behind * shallow * 1.4 * (1.0 - k);
	// Each 0.25 m cell tilts a little and changes a few times a second: blocky glints that
	// match the ground, not a smooth mirror.
	// Looking across the water at a low angle the glints and the sky's reflection would wash it
	// to white, so both fade as the view flattens.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec2 centre = (snapped + 0.5) * cell;
	float ring = 0.0;
	vec2 push = vec2(0.0);
	for (int i = 0; i < 16; i++) {
		vec4 r = ripples[i];
		float age = now - r.z;
		if (r.w <= 0.0 || age < 0.0 || age > ripple_seconds) {
			continue;
		}
		vec2 away = centre - r.xy;
		float dist = length(away);
		float band = 1.0 - smoothstep(0.0, cell * 1.5, abs(dist - age * ripple_speed));
		float strength = band * (1.0 - age / ripple_seconds) * r.w;
		ring += strength;
		push += away / max(dist, 0.001) * strength;
	}
	ring = clamp(ring, 0.0, 1.0);
	ALBEDO += vec3(0.22) * ring;
	vec3 tilt = vec3(hash(snapped + t * 1.7) - 0.5, 0.0, hash(snapped.yx + t * 2.3) - 0.5) * 0.06 * mix(0.12, 1.0, facing * facing);
	tilt += vec3(push.x, 0.0, push.y) * 0.25;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(tilt, 0.0)).xyz);
	ROUGHNESS = mix(0.18, 0.08, facing);
	SPECULAR = mix(0.32, 0.5, facing);
	METALLIC = 0.0;
	ALPHA = 1.0;
}
"""

const MAX_RIPPLES := 16
## Groups whose members leave ripples as they move through water.
const WADERS: Array[StringName] = [&"players", &"enemies", &"vehicles"]
## Waders further than this from the camera leave none.
const WADE_REACH := 60.0
const WADE_EVERY := 0.35
const WADE_MOVED := 0.2

var water: WaterBodies
## The `water` block of world.json.
var config: Dictionary = {}

var _material: ShaderMaterial
var _ripples := PackedVector4Array()
var _next_ripple := 0
var _clock := 0.0
var _wade_in := 0.0
## Wader instance id -> where it was at the last check.
var _last_at: Dictionary[int, Vector3] = {}


func _ready() -> void:
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter(&"shallow", _colour(config.get("shallow", [0.32, 0.5, 0.45])))
	_material.set_shader_parameter(&"deep", _colour(config.get("deep", [0.05, 0.16, 0.2])))
	_material.set_shader_parameter(&"colour_depth", float(config.get("colour_depth", 3.0)))
	_material.set_shader_parameter(&"ripple_speed", float(config.get("ripple_speed", 1.5)))
	_material.set_shader_parameter(&"ripple_seconds", float(config.get("ripple_seconds", 1.5)))
	_ripples.resize(MAX_RIPPLES)
	_material.set_shader_parameter(&"ripples", _ripples)
	for i in water.bodies.size():
		_add_surface(surface_mesh(water.bodies[i]["outline"], water.level_of(i)), "Body%d" % i)
	for puddle in water.puddles:
		add_puddle(puddle)
	EventBus.subscribe(&"weapon.fired", _on_fired)
	EventBus.subscribe(&"explosion", _on_explosion)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"weapon.fired", _on_fired)
	EventBus.unsubscribe(&"explosion", _on_explosion)


func _add_surface(mesh: ArrayMesh, part_name: String) -> void:
	if mesh == null:
		return
	mesh.surface_set_material(0, _material)
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)


## A crater that filled with water: Vector4(x, z, radius at the surface, level). A square
## over the bowl at the level: wherever the ground is still above the water it hides the
## surface, so the water's edge follows the crater's own stepped voxel edge.
func add_puddle(puddle: Vector4) -> void:
	var r := puddle.z + 0.5
	var outline := PackedVector2Array([
		Vector2(puddle.x - r, puddle.y - r), Vector2(puddle.x + r, puddle.y - r),
		Vector2(puddle.x + r, puddle.y + r), Vector2(puddle.x - r, puddle.y + r),
	])
	_add_surface(surface_mesh(outline, puddle.w), "Puddle%d" % get_child_count())


func _process(delta: float) -> void:
	var t := Prof.start()
	_clock += delta
	_material.set_shader_parameter(&"now", _clock)
	_wade_in -= delta
	if _wade_in <= 0.0:
		_wade_in = WADE_EVERY
		_ripple_waders()
	Prof.stop(&"world/water", t)


## A ring starting at `at` on the water; `strength` 0..1.
func add_ripple(at: Vector3, strength: float) -> void:
	_ripples[_next_ripple] = Vector4(at.x, at.z, _clock, strength)
	_next_ripple = (_next_ripple + 1) % MAX_RIPPLES
	if _material != null:
		_material.set_shader_parameter(&"ripples", _ripples)


func ripple_count() -> int:
	var n := 0
	for r in _ripples:
		if r.w > 0.0:
			n += 1
	return n


## Where a straight line from `from` to `to` passes down through a surface at `level`, or
## null if it doesn't.
static func crossing(from: Vector3, to: Vector3, level: float) -> Variant:
	if is_nan(level) or from.y < level or to.y > level or is_equal_approx(from.y, to.y):
		return null
	return from.lerp(to, (from.y - level) / (from.y - to.y))


func _on_fired(p: Dictionary) -> void:
	if not p.has("to"):
		return
	var to: Vector3 = p["to"]
	var from: Vector3 = p.get("from", to)
	var hit: Variant = crossing(from, to, water.level_at(to.x, to.z))
	if hit is Vector3:
		add_ripple(hit, 0.7)
		_splash(hit, 10, 2.5)


func _on_explosion(p: Dictionary) -> void:
	var at: Vector3 = p.get("position", Vector3.INF)
	var level := water.level_at(at.x, at.z)
	if at == Vector3.INF or is_nan(level) or at.y > level + 1.5:
		return
	var surface := Vector3(at.x, level, at.z)
	add_ripple(surface, 1.0)
	add_ripple(surface, 0.6)
	_splash(surface, 40, 7.0)


func _ripple_waders() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye := camera.global_position
	var seen: Dictionary[int, Vector3] = {}
	for group in WADERS:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body == null or not body.is_visible_in_tree() or body.global_position.distance_to(eye) > WADE_REACH:
				continue
			var at := body.global_position
			var level := water.level_at(at.x, at.z)
			if is_nan(level) or at.y > level + 0.3:
				continue
			var id := body.get_instance_id()
			seen[id] = at
			if _last_at.has(id) and _last_at[id].distance_to(at) > WADE_MOVED:
				add_ripple(Vector3(at.x, level, at.z), 0.45)
	_last_at = seen


## White drops thrown up from `at`, `count` of them, at up to `speed`.
func _splash(at: Vector3, count: int, speed: float) -> void:
	var burst := CPUParticles3D.new()
	burst.one_shot = true
	burst.explosiveness = 0.95
	burst.amount = count
	burst.lifetime = 0.9
	burst.direction = Vector3.UP
	burst.spread = 25.0
	burst.initial_velocity_min = speed * 0.4
	burst.initial_velocity_max = speed
	burst.gravity = Vector3(0, -9.8, 0)
	burst.scale_amount_min = 0.6
	burst.scale_amount_max = 1.4
	var drop := BoxMesh.new()
	drop.size = Vector3.ONE * 0.08
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.92, 0.95)
	material.roughness = 0.2
	drop.material = material
	burst.mesh = drop
	add_child(burst)
	burst.global_position = at
	burst.emitting = true
	burst.finished.connect(burst.queue_free)


static func _colour(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))


## The outline filled in, flat at `level`, facing up; null if it can't be filled.
static func surface_mesh(outline: PackedVector2Array, level: float) -> ArrayMesh:
	var triangles := Geometry2D.triangulate_polygon(outline)
	if triangles.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	# Wound so the faces look up.
	var clockwise := Geometry2D.is_polygon_clockwise(outline)
	for t in range(0, triangles.size(), 3):
		var order := [0, 2, 1] if clockwise else [0, 1, 2]
		for o: int in order:
			var p := outline[triangles[t + o]]
			st.add_vertex(Vector3(p.x, level, p.y))
	return st.commit()

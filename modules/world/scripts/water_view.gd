class_name WaterView
extends Node3D
## Client: one flat surface per pond at its level (and the sea's over the sea, #454, with its
## own look: `sea` in the config), shaded by how much water is under each
## spot (shallow tint at the edge to deep tint `colour_depth` metres down), with what is
## under the surface showing through, on a 0.25 m grid so it stays blocky like the ground.
## A light band where it thins out at the shore, slow blocky waves drifting with `wind`, and
## the sky's tint as you look across it. Flooded craters get the same surface over their bowl.
## The sea's waves are larger and stronger, and foam runs in to its shore in broken lines.
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
uniform vec3 shallow : source_color = vec3(0.42, 0.68, 0.52);
uniform vec3 deep : source_color = vec3(0.09, 0.36, 0.26);
uniform vec3 shore : source_color = vec3(0.5, 0.75, 0.68);
uniform vec3 sky : source_color = vec3(0.62, 0.71, 0.78);
uniform float colour_depth = 3.0;
// Water shallower than this (metres) at the edge shows as a light band.
uniform float shore_depth = 0.2;
uniform float cell = 0.25;
// Metres a second the wave pattern drifts, x and z.
uniform vec2 wind = vec2(0.6, 0.25);
// x, z, when it started (`now`'s clock), strength (0: unused).
uniform vec4 ripples[16];
uniform float now;
uniform float ripple_speed = 1.5;
uniform float ripple_seconds = 1.5;
// Below 1 the wave pattern grows larger; wave_strength scales how much the crests stand out.
uniform float wave_scale = 1.0;
uniform float wave_strength = 1.0;
// Foam within foam_depth metres of water against the ground (0: none), in lines that run in
// to the shore at foam_speed.
uniform vec3 foam : source_color = vec3(0.92, 0.95, 0.95);
uniform float foam_depth = 0.0;
uniform float foam_speed = 0.3;
// The water's depth from the map (metres, red), over `depth_map_rect` (x, z, width, depth):
// where no ground is built under the surface (past the terrain's reach) the eye would look
// through to nothing, so the depth comes from here instead.
uniform sampler2D depth_map : filter_linear, repeat_disable;
uniform vec4 depth_map_rect = vec4(0.0);
// What the floor looks like through the water where none is drawn (as lit, before the tint).
uniform vec3 bed : source_color = vec3(0.0);
uniform float bed_distance = 100000.0;
varying vec3 world;
// Metres past which what the depth texture holds is the sky (at infinity), not ground.
const float NOTHING_PAST = 1000000.0;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth value noise, sampled per cell so the waves stay blocky.
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float waves(vec2 at) {
	vec2 drift = wind * now;
	return noise((at + drift) * 0.35 * wave_scale) * 0.65 + noise((at - drift * 0.6) * 0.9 * wave_scale) * 0.35;
}

void fragment() {
	vec2 snapped = floor(world.xz / cell);
	vec2 centre = (snapped + 0.5) * cell;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// Waves: drifting light and dark patches, a few steps of brightness per cell.
	float w = waves(centre);
	// Two hard-edged shades, crests and troughs, so the waves read as blocks, not smudges.
	float band_w = step(0.52, w);
	vec2 slope = vec2(waves(centre + vec2(cell, 0.0)) - w, waves(centre + vec2(0.0, cell)) - w);
	vec2 uv = SCREEN_UV + slope * 0.02;
	float d = texture(depth_tex, uv).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, d, 1.0);
	view.xyz /= view.w;
	// How much water the eye looks through to reach what is behind the surface here.
	float through = max(length(view.xyz) - length(VERTEX), 0.0);
	// What shows through the water: `bed` where nothing is drawn under it.
	float seen = 1.0;
	// How much water the colour goes by: what the eye looks through, or with the map's depth
	// (the sea) that depth slanted by the view, so the colour neither steps where coarser
	// ground is drawn further off nor turns to open ocean past where any ground is drawn.
	float colour_through = through;
	if (depth_map_rect.z > 0.0) {
		float known = texture(depth_map, (world.xz - depth_map_rect.xy) / depth_map_rect.zw).r;
		colour_through = known / max(facing, 0.15);
		// Nothing drawn there reads as the far plane (or past it, at infinity).
		if (!(length(view.xyz) < NOTHING_PAST)) {
			through = colour_through;
			seen = 0.0;
		}
	}
	if (-view.z < -VERTEX.z) {
		// Something in front of the water: don't refract it in.
		uv = SCREEN_UV;
		through = 0.0;
		colour_through = 0.0;
	}
	float k = clamp(colour_through / colour_depth, 0.0, 1.0);
	vec3 behind = texture(screen, uv).rgb;
	vec3 tint = mix(shallow, deep, sqrt(k));
	// What is under the water was lit already: it shows through as emission, fading with depth,
	// so it isn't lit twice; the water's own tint takes the light.
	vec3 albedo = tint * (0.6 + 0.4 * k) * (0.85 + band_w * mix(0.45, 0.3, facing) * wave_strength);
	// Further off than `bed_distance` the floor shows as `bed`: the ground drawn there is
	// coarser and past the sun's shadows, and would show through in patches.
	seen *= 1.0 - smoothstep(bed_distance * 0.6, bed_distance, length(VERTEX));
	EMISSION = mix(bed, behind, seen) * shallow * 1.2 * (1.0 - k);
	// A light band where the water thins out against the ground.
	float edge = 1.0 - smoothstep(shore_depth * 0.4, shore_depth, through);
	albedo = mix(albedo, shore, edge * 0.65);
	if (foam_depth > 0.0) {
		// Lines of foam rolling in, broken up into patches, and a solid rim at the waterline.
		float near_shore = 1.0 - smoothstep(foam_depth * 0.3, foam_depth, through);
		float lines = step(0.6, fract(through / foam_depth * 1.5 + now * foam_speed));
		float broken = step(0.4, noise(centre * 0.5 + vec2(now * 0.2, 0.0)));
		float rim = 1.0 - smoothstep(foam_depth * 0.08, foam_depth * 0.2, through);
		albedo = mix(albedo, foam, clamp(rim + near_shore * lines * broken * 0.75, 0.0, 1.0));
	}
	// Looking across it, water shows the sky; kept a tint, not a white mirror.
	albedo = mix(albedo, sky, pow(1.0 - facing, 2.5) * 0.3);
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
	ALBEDO = albedo + vec3(0.3) * ring;
	// Now and then a cell catches the sun: a few bright specks that move, most from low angles.
	// Only further off: up close a lit cell is a white tile, not a sparkle.
	float far = smoothstep(10.0, 25.0, length(VERTEX));
	// Glints are the sun off wave faces seen at a low angle; from above there are none.
	float glint = step(0.997, hash(snapped + floor(now * 4.0))) * smoothstep(0.6, 0.2, facing);
	EMISSION += vec3(0.9, 0.95, 1.0) * glint * 0.45 * far;
	vec3 tilt = vec3(slope.x, 0.0, slope.y) * 0.6 * wave_strength * mix(0.2, 1.0, facing) + vec3(push.x, 0.0, push.y) * 0.25;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(tilt, 0.0)).xyz);
	ROUGHNESS = mix(0.3, 0.12, facing);
	SPECULAR = mix(0.12, 0.35, facing);
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
## The sea's: the same shader with the sea's look; null on a map without one.
var _sea_material: ShaderMaterial
var _ripples := PackedVector4Array()
var _next_ripple := 0
var _clock := 0.0
var _wade_in := 0.0
## Wader instance id -> where it was at the last check.
var _last_at: Dictionary[int, Vector3] = {}


func _ready() -> void:
	var shader := Shader.new()
	shader.code = SHADER
	_ripples.resize(MAX_RIPPLES)
	_material = _make_material(shader, config)
	for i in water.bodies.size():
		var body := water.bodies[i]
		if body.get("sea", false):
			# The sea's look over the pond's: what it leaves out stays as a pond's.
			var look := config.duplicate()
			look.merge(config.get("sea", {}), true)
			# The sea takes no shadows: far off, the sun's shadows end in a hard line across it.
			var sea_shader := Shader.new()
			sea_shader.code = SHADER.replace("depth_draw_always;", "depth_draw_always, shadows_disabled;")
			_sea_material = _make_material(sea_shader, look)
			var land := (water as MapWater).land if water is MapWater else null
			var depths := land.sea_depth_image() if land != null else null
			if depths != null:
				_sea_material.set_shader_parameter(&"depth_map", ImageTexture.create_from_image(depths))
				var rect := land.sea_depth_rect()
				_sea_material.set_shader_parameter(&"depth_map_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
			_add_surface(sea_mesh(water, water.level_of(i)), "Sea", _sea_material)
			continue
		# A map's pond over its own cells: its outline is a hull that may reach over the sea.
		if water is MapWater and (water as MapWater).land != null:
			_add_surface(rects_mesh((water as MapWater).land.pond_runs(i), water.level_of(i)), "Body%d" % i)
		else:
			_add_surface(surface_mesh(body["outline"], water.level_of(i)), "Body%d" % i)
	for puddle in water.puddles:
		add_puddle(puddle)
	EventBus.subscribe(&"weapon.fired", _on_fired)
	EventBus.subscribe(&"explosion", _on_explosion)
	# Other modules find it here to pour puddles (`drape`) and ripple them.
	add_to_group(&"water_view")


func _exit_tree() -> void:
	EventBus.unsubscribe(&"weapon.fired", _on_fired)
	EventBus.unsubscribe(&"explosion", _on_explosion)


func _make_material(shader: Shader, look: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"shallow", _colour(look.get("shallow", [0.42, 0.68, 0.52])))
	material.set_shader_parameter(&"deep", _colour(look.get("deep", [0.09, 0.36, 0.26])))
	material.set_shader_parameter(&"colour_depth", float(look.get("colour_depth", 3.0)))
	material.set_shader_parameter(&"shore", _colour(look.get("shore_colour", [0.5, 0.75, 0.68])))
	material.set_shader_parameter(&"sky", _colour(look.get("sky", [0.62, 0.71, 0.78])))
	material.set_shader_parameter(&"shore_depth", float(look.get("shore_depth", 0.2)))
	var wind: Array = look.get("wind", [0.6, 0.25])
	material.set_shader_parameter(&"wind", Vector2(float(wind[0]), float(wind[1])))
	material.set_shader_parameter(&"ripple_speed", float(look.get("ripple_speed", 1.5)))
	material.set_shader_parameter(&"ripple_seconds", float(look.get("ripple_seconds", 1.5)))
	material.set_shader_parameter(&"wave_scale", float(look.get("wave_scale", 1.0)))
	material.set_shader_parameter(&"wave_strength", float(look.get("wave_strength", 1.0)))
	material.set_shader_parameter(&"foam", _colour(look.get("foam", [0.92, 0.95, 0.95])))
	material.set_shader_parameter(&"foam_depth", float(look.get("foam_depth", 0.0)))
	material.set_shader_parameter(&"foam_speed", float(look.get("foam_speed", 0.3)))
	material.set_shader_parameter(&"bed", _colour(look.get("bed", [0.0, 0.0, 0.0])))
	material.set_shader_parameter(&"bed_distance", float(look.get("bed_distance", 100000.0)))
	material.set_shader_parameter(&"ripples", _ripples)
	return material


func _add_surface(mesh: ArrayMesh, part_name: String, material: ShaderMaterial = null) -> void:
	if mesh == null or mesh.get_surface_count() == 0:
		return
	mesh.surface_set_material(0, material if material != null else _material)
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


## A thin sheet of water lying on the ground, `radius` around `centre`, one flat cell per
## 0.5 m at the ground's height there (`height_at(x, z)`) plus `film`: a puddle poured out of something. Called again
## with the same `key` it replaces that puddle (one that grew).
func drape(key: String, centre: Vector3, radius: float, height_at: Callable, film := 0.04) -> void:
	var old := get_node_or_null(NodePath("Drape_" + key))
	if old != null:
		old.free()
	if radius <= 0.05:
		return
	var step := 0.5
	var n := int(ceil(radius / step))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in range(-n, n):
		for j in range(-n, n):
			var x0 := centre.x + i * step
			var z0 := centre.z + j * step
			# Whole cells inside the circle, so its edge steps like the voxel ground.
			if Vector2(x0 + step / 2.0 - centre.x, z0 + step / 2.0 - centre.z).length() > radius:
				continue
			# One height per cell, from its middle: on stepped ground the sheet steps too,
			# instead of bridging over the drops.
			var y := float(height_at.call(x0 + step / 2.0, z0 + step / 2.0)) + film
			var corners: Array[Vector3] = [Vector3(x0, y, z0), Vector3(x0 + step, y, z0), Vector3(x0 + step, y, z0 + step), Vector3(x0, y, z0 + step)]
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(corners[k])
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	_add_surface(mesh, "Drape_" + key)


func _process(delta: float) -> void:
	var t := Prof.start()
	_clock += delta
	_material.set_shader_parameter(&"now", _clock)
	if _sea_material != null:
		_sea_material.set_shader_parameter(&"now", _clock)
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
	if _sea_material != null:
		_sea_material.set_shader_parameter(&"ripples", _ripples)


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


## The sea's surface at `level`: a quad over each run of the sea's cells on the map
## (WorldLand.sea_runs) and a frame round the map out to the sea body's outline, so the
## horizon is water but no inland hollow below sea level gets the sea's surface. Null
## without a sea.
static func sea_mesh(bodies: WaterBodies, level: float) -> ArrayMesh:
	if not bodies is MapWater or (bodies as MapWater).land == null or (bodies as MapWater).sea < 0:
		return null
	var map_water := bodies as MapWater
	var rects := map_water.land.sea_runs()
	var inner := map_water.land.bounds()
	var outer: Rect2 = map_water.bodies[map_water.sea]["box"]
	rects.append(Rect2(outer.position, Vector2(outer.size.x, inner.position.y - outer.position.y)))
	rects.append(Rect2(Vector2(outer.position.x, inner.end.y), Vector2(outer.size.x, outer.end.y - inner.end.y)))
	rects.append(Rect2(Vector2(outer.position.x, inner.position.y), Vector2(inner.position.x - outer.position.x, inner.size.y)))
	rects.append(Rect2(Vector2(inner.end.x, inner.position.y), Vector2(outer.end.x - inner.end.x, inner.size.y)))
	return rects_mesh(rects, level)


## Flat quads at `level` over `rects` (x, z), facing up; null for none.
static func rects_mesh(rects: Array[Rect2], level: float) -> ArrayMesh:
	if rects.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for r in rects:
		var a := Vector3(r.position.x, level, r.position.y)
		var b := Vector3(r.end.x, level, r.position.y)
		var c := Vector3(r.end.x, level, r.end.y)
		var d := Vector3(r.position.x, level, r.end.y)
		# Wound to face up.
		for v: Vector3 in [a, b, c, a, c, d]:
			st.add_vertex(v)
	return st.commit()


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

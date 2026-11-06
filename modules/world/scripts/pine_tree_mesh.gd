class_name PineTreeMesh
extends RefCounted
## Builds a game-ready conifer: a tapered bark trunk plus whorls of drooping branch cards
## that shrink toward the crown, each crossed with a second card for volume. Two surfaces
## (bark, foliage) in one mesh, so a MultiMesh draws whole trees. Feet at the origin.

const BARK := "res://modules/world/textures/Bark014/Bark014_1K-JPG_"
const BRANCH := "res://modules/world/textures/generated/pine_branch.png"
const FOLIAGE_SHADER := "res://modules/world/shaders/foliage.gdshader"


static func build(seed_value: int, height: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mesh := ArrayMesh.new()
	_trunk(mesh, height, rng)
	_crown(mesh, height, rng)
	return mesh


static func _trunk(mesh: ArrayMesh, height: float, rng: RandomNumberGenerator) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 8
	var base_r := height * 0.028 * rng.randf_range(0.9, 1.15)
	var rings := 6
	for ring in rings:
		var y0 := height * float(ring) / rings
		var y1 := height * float(ring + 1) / rings
		var r0 := base_r * (1.0 - 0.85 * float(ring) / rings)
		var r1 := base_r * (1.0 - 0.85 * float(ring + 1) / rings)
		for i in sides:
			var a0 := TAU * float(i) / sides
			var a1 := TAU * float(i + 1) / sides
			var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p10 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p01 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			# UV: around the trunk, and along it at roughly bark-texture scale.
			var u0 := float(i) / sides
			var u1 := float(i + 1) / sides
			var v0 := y0 / 1.2
			var v1 := y1 / 1.2
			_bark_quad(st, [p00, p10, p11, p01], [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])
	st.generate_normals()
	st.generate_tangents()
	st.commit(mesh)
	var bark := StandardMaterial3D.new()
	bark.albedo_texture = load(BARK + "Color.jpg")
	bark.normal_enabled = true
	bark.normal_texture = load(BARK + "NormalGL.jpg")
	bark.albedo_color = Color(0.7, 0.66, 0.62)
	bark.roughness = 0.95
	mesh.surface_set_material(mesh.get_surface_count() - 1, bark)


## Quad wound so the outside faces out (Godot front faces are clockwise from the front).
static func _bark_quad(st: SurfaceTool, p: Array, uv: Array) -> void:
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[idx])
		st.add_vertex(p[idx])


static func _crown(mesh: ArrayMesh, height: float, rng: RandomNumberGenerator) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crown_start := height * rng.randf_range(0.18, 0.28)
	var whorls := int(height * 1.4)
	var twist := rng.randf() * TAU
	for w in whorls:
		var t := float(w) / maxf(whorls - 1, 1)
		var y := lerpf(crown_start, height * 0.97, t)
		# Cone silhouette with a slight bulge low down, as real firs have.
		var length := lerpf(height * 0.32, height * 0.06, pow(t, 0.85)) * rng.randf_range(0.9, 1.1)
		var count := 8 if t < 0.7 else 5
		twist += rng.randf_range(0.5, 1.1)
		for b in count:
			var angle := twist + TAU * float(b) / count + rng.randf_range(-0.2, 0.2)
			var droop := deg_to_rad(lerpf(28.0, 8.0, t) + rng.randf_range(-6.0, 6.0))
			_branch(st, Vector3(0, y, 0), angle, droop, length, height)
	# A short upright leader at the very top.
	_branch(st, Vector3(0, height * 0.92, 0), twist, deg_to_rad(-70.0), height * 0.1, height)
	st.commit(mesh)
	var foliage := ShaderMaterial.new()
	foliage.shader = load(FOLIAGE_SHADER)
	foliage.set_shader_parameter("needles", load(BRANCH))
	mesh.surface_set_material(mesh.get_surface_count() - 1, foliage)


## One branch: two crossed cards from the trunk outward, drooping by `droop` radians.
static func _branch(st: SurfaceTool, root: Vector3, angle: float, droop: float, length: float, height: float) -> void:
	var dir := Vector3(cos(angle), -sin(droop), sin(angle)).normalized()
	var side := Vector3(-sin(angle), 0.0, cos(angle))
	var width := length * 0.62
	for roll in [0.0, PI / 2.0]:
		# Second card is rolled 90 degrees around the branch so it has volume from any angle.
		var across := side.rotated(dir, roll) * width * 0.5
		var tip := root + dir * length
		var corners := [root - across, tip - across, tip + across, root + across]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			var p: Vector3 = corners[idx]
			# Normals point away from the trunk and a little up: soft, volumetric crown light.
			var outward := Vector3(p.x, 0.0, p.z).normalized() * 0.8 + Vector3.UP * (0.4 + p.y / height * 0.3)
			st.set_normal(outward.normalized())
			st.set_color(Color.WHITE)
			st.set_uv(uvs[idx])
			st.add_vertex(p)

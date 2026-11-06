class_name PineTreeMesh
extends RefCounted
## Builds game-ready conifers in a few species: a tapered bark trunk, bark-textured limbs,
## and whorls of drooping needle cards (crossed for volume). Two surfaces (bark, foliage)
## in one mesh, so a MultiMesh draws whole trees. Feet at the origin.
##
## Styles:
##   fir     - full to near the ground, classic cone
##   spruce  - tall and narrow, dense
##   pine    - long bare trunk with dead stubs, flat-topped crown high up
##   sapling - small, bushy, branches almost to the ground
##   dead    - bare trunk and limbs, no needles

const BARK := "res://modules/world/textures/Bark014/Bark014_1K-JPG_"
const BRANCH := "res://modules/world/textures/generated/pine_branch.png"
const FOLIAGE_SHADER := "res://modules/world/shaders/foliage.gdshader"

## crown_start: fraction of height where needles begin; spread: crown radius relative to
## height; density: whorls per metre; droop: degrees at the bottom and top of the crown;
## taper: how much the crown narrows toward the top (1 = cone, 0 = column); stubs: dead
## branch stubs on the bare lower trunk, per metre of bare trunk.
const STYLES := {
	"fir": {"crown_start": [0.15, 0.25], "spread": 0.32, "density": 1.4, "droop": [28.0, 8.0], "taper": 0.85, "per_whorl": 8, "foliage": true, "stubs": 0.0},
	"spruce": {"crown_start": [0.1, 0.2], "spread": 0.2, "density": 1.8, "droop": [35.0, 12.0], "taper": 0.95, "per_whorl": 9, "foliage": true, "stubs": 0.0},
	"pine": {"crown_start": [0.4, 0.5], "spread": 0.3, "density": 1.7, "droop": [6.0, -4.0], "taper": 0.45, "per_whorl": 8, "foliage": true, "stubs": 1.2},
	"sapling": {"crown_start": [0.03, 0.08], "spread": 0.38, "density": 2.4, "droop": [20.0, 5.0], "taper": 0.9, "per_whorl": 6, "foliage": true, "stubs": 0.0},
	"dead": {"crown_start": [0.3, 0.45], "spread": 0.22, "density": 0.9, "droop": [10.0, -10.0], "taper": 0.7, "per_whorl": 4, "foliage": false, "stubs": 1.0},
}


static func build(seed_value: int, height: float, style_name: String = "fir") -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var style: Dictionary = STYLES[style_name]
	var mesh := ArrayMesh.new()
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var foliage := SurfaceTool.new()
	foliage.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Thin enough that crowns hide it; thick trunks read as poles through the needles.
	var trunk_radius := height * 0.019 * rng.randf_range(0.9, 1.1)
	_tapered_limb(bark, Vector3.ZERO, Vector3(0, height, 0), trunk_radius, trunk_radius * 0.15, 8, 6)
	_crown(bark, foliage, height, trunk_radius, style, rng)
	bark.generate_normals()
	bark.generate_tangents()
	bark.commit(mesh)
	mesh.surface_set_material(0, _bark_material())
	if style["foliage"]:
		foliage.commit(mesh)
		var mat := ShaderMaterial.new()
		mat.shader = load(FOLIAGE_SHADER)
		mat.set_shader_parameter("needles", load(BRANCH))
		mesh.surface_set_material(1, mat)
	return mesh


static func _bark_material() -> StandardMaterial3D:
	var bark := StandardMaterial3D.new()
	bark.albedo_texture = load(BARK + "Color.jpg")
	bark.normal_enabled = true
	bark.normal_texture = load(BARK + "NormalGL.jpg")
	bark.albedo_color = Color(0.7, 0.66, 0.62)
	bark.roughness = 0.95
	return bark


## A tapered, UV-mapped cylinder from `a` to `b`: trunk, limbs and stubs.
static func _tapered_limb(st: SurfaceTool, a: Vector3, b: Vector3, r_a: float, r_b: float, sides: int, rings: int) -> void:
	var axis := b - a
	var length := axis.length()
	var up := axis / length
	var helper := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var side := up.cross(helper).normalized()
	var other := up.cross(side)
	for ring in rings:
		var t0 := float(ring) / rings
		var t1 := float(ring + 1) / rings
		var c0 := a + axis * t0
		var c1 := a + axis * t1
		var r0 := lerpf(r_a, r_b, t0)
		var r1 := lerpf(r_a, r_b, t1)
		for i in sides:
			var a0 := TAU * float(i) / sides
			var a1 := TAU * float(i + 1) / sides
			var d0 := side * cos(a0) + other * sin(a0)
			var d1 := side * cos(a1) + other * sin(a1)
			var quad: Array[Vector3] = [c0 + d0 * r0, c0 + d1 * r0, c1 + d1 * r1, c1 + d0 * r1]
			var u0 := float(i) / sides
			var u1 := float(i + 1) / sides
			var v0 := length * t0 / 1.2
			var v1 := length * t1 / 1.2
			var uvs: Array[Vector2] = [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
			_oriented_quad(st, quad, uvs, (c0 + c1) * 0.5)


## Emits a quad facing away from `inside`, fixing winding geometrically (see LowPoly._tri).
static func _oriented_quad(st: SurfaceTool, p: Array[Vector3], uv: Array[Vector2], inside: Vector3) -> void:
	var order := [0, 1, 2, 0, 2, 3]
	var n := (p[1] - p[0]).cross(p[2] - p[0])
	var centre := (p[0] + p[1] + p[2] + p[3]) / 4.0
	# Godot front faces wind clockwise, so a front face's cross product points inward.
	if n.dot(centre - inside) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for idx: int in order:
		st.set_uv(uv[idx])
		st.add_vertex(p[idx])


static func _crown(bark: SurfaceTool, foliage: SurfaceTool, height: float, trunk_r: float, style: Dictionary, rng: RandomNumberGenerator) -> void:
	var range_start: Array = style["crown_start"]
	var crown_start := height * rng.randf_range(range_start[0], range_start[1])
	var whorls := maxi(3, int((height - crown_start) * float(style["density"])))
	var droop_range: Array = style["droop"]
	var twist := rng.randf() * TAU
	# Dead stubs along the bare lower trunk: what is left of branches that died off.
	var stubs := int(crown_start * float(style["stubs"]))
	for s in stubs:
		var y := rng.randf_range(height * 0.12, crown_start)
		var angle := rng.randf() * TAU
		var dir := Vector3(cos(angle), rng.randf_range(-0.3, 0.1), sin(angle)).normalized()
		var r := _trunk_radius_at(trunk_r, y, height)
		_tapered_limb(bark, Vector3(0, y, 0), Vector3(0, y, 0) + dir * rng.randf_range(0.3, 0.9), r * 0.35, r * 0.08, 4, 1)
	for w in whorls:
		var t := float(w) / maxf(whorls - 1, 1)
		var y := lerpf(crown_start, height * 0.97, t)
		var length := height * float(style["spread"]) * lerpf(1.0, 1.0 - float(style["taper"]), pow(t, 0.85)) * rng.randf_range(0.85, 1.15)
		var count := int(style["per_whorl"]) if t < 0.7 else maxi(3, int(style["per_whorl"]) - 3)
		twist += rng.randf_range(0.5, 1.1)
		for b in count:
			var angle := twist + TAU * float(b) / count + rng.randf_range(-0.25, 0.25)
			var droop := deg_to_rad(lerpf(droop_range[0], droop_range[1], t) + rng.randf_range(-6.0, 6.0))
			var dir := Vector3(cos(angle), -sin(droop), sin(angle)).normalized()
			var root := Vector3(0, y, 0)
			var r := _trunk_radius_at(trunk_r, y, height)
			# The woody limb under the needles, reaching most of the way out.
			_tapered_limb(bark, root, root + dir * length * 0.75, r * 0.4, r * 0.08, 4, 1)
			if style["foliage"]:
				_branch_cards(foliage, root, dir, angle, length, height)
	if style["foliage"]:
		# A short upright leader at the very top.
		_branch_cards(foliage, Vector3(0, height * 0.92, 0), Vector3(0.15, 1, 0).normalized(), twist, height * 0.1, height)


static func _trunk_radius_at(base_r: float, y: float, height: float) -> float:
	return lerpf(base_r, base_r * 0.15, clampf(y / height, 0.0, 1.0))


## Two crossed needle cards along `dir` from the trunk outward.
static func _branch_cards(st: SurfaceTool, root: Vector3, dir: Vector3, angle: float, length: float, height: float) -> void:
	var side := Vector3(-sin(angle), 0.0, cos(angle))
	var width := length * 0.62
	for roll: float in [0.0, PI / 2.0]:
		# Second card is rolled 90 degrees around the branch so it has volume from any angle.
		var across := side.rotated(dir, roll) * width * 0.5
		var tip := root + dir * length
		var corners: Array[Vector3] = [root - across, tip - across, tip + across, root + across]
		var uvs: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx: int in [0, 1, 2, 0, 2, 3]:
			var p := corners[idx]
			# Normals point away from the trunk and a little up: soft, volumetric crown light.
			var outward := Vector3(p.x, 0.0, p.z).normalized() * 0.8 + Vector3.UP * (0.4 + p.y / height * 0.3)
			st.set_normal(outward.normalized())
			st.set_color(Color.WHITE)
			st.set_uv(uvs[idx])
			st.add_vertex(p)

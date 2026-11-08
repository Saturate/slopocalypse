class_name SceneryScatter
extends Node3D
## Scatters firs, rocks and grass over the terrain by biome (forests, meadows, dry and rocky
## ground) from a seed, so the server
## and every client place the same trees in the same spots. Trees and rocks get collision
## everywhere; the visuals (and grass, which has no collision) are client-only.

@export_file("*.json") var config_path: String = "res://modules/world/data/world.json"

const REQUIRED := {"trees": TYPE_FLOAT, "rocks": TYPE_FLOAT, "grass": TYPE_FLOAT, "clear_radius": TYPE_FLOAT, "max_steepness": TYPE_FLOAT, "seed": TYPE_FLOAT}

var _heights: TerrainHeights
var _biomes: Biomes
var _rng := RandomNumberGenerator.new()
var _visual := DisplayServer.get_name() != "headless"
## Grass, and its tufts bucketed by GRASS_CELL so a dig only checks the tufts near it.
var _grass: MultiMesh
var _grass_cells: Dictionary[Vector2i, PackedInt32Array] = {}

const GRASS_CELL := 8.0
## The smoothed terrain sags a little past a dug sphere's edge, and the shader shows that
## fringe as dirt, so grass clears slightly wider than the hole.
const GRASS_CLEAR_MARGIN := 0.4
## Rocks whose top is lower than this above the ground get no collision; feet clear them.
const STEP_OVER_HEIGHT := 0.3


func _ready() -> void:
	var data: Variant = Data.load_json(config_path)
	if not data is Dictionary or not Data.require(config_path, data, TerrainHeights.REQUIRED):
		return
	var world: Dictionary = data
	if not world.has("scatter") or not Data.require(config_path + " scatter", world["scatter"], REQUIRED):
		return
	var cfg: Dictionary = world["scatter"]
	if not world.has("biomes") or not Data.require(config_path + " biomes", world["biomes"], Biomes.REQUIRED):
		return
	_heights = TerrainHeights.new(world)
	_biomes = Biomes.new(world["biomes"])
	var collision := StaticBody3D.new()
	collision.name = "SceneryCollision"
	add_child(collision)
	_rng.seed = int(cfg["seed"])
	_place_trees(int(cfg["trees"]), cfg, collision)
	_place_rocks(int(cfg["rocks"]), cfg, collision)
	if _visual:
		_place_grass(int(cfg["grass"]), cfg)


## A spot on gentle ground, away from the spawn pad and the chunk edge, kept with the
## probability `weight(x, z)` returns, so biomes decide where things cluster.
func _random_spot(cfg: Dictionary, weight: Callable) -> Variant:
	var half := _heights.size / 2.0 - 6.0
	for attempt in 12:
		var x := _rng.randf_range(-half, half)
		var z := _rng.randf_range(-half, half)
		if Vector2(x, z).length() < float(cfg["clear_radius"]):
			continue
		if _rng.randf() > float(weight.call(x, z)):
			continue
		var s := 1.0
		var dx := _heights.height_at(x + s, z) - _heights.height_at(x - s, z)
		var dz := _heights.height_at(x, z + s) - _heights.height_at(x, z - s)
		if Vector2(dx, dz).length() / (2.0 * s) > float(cfg["max_steepness"]):
			continue
		return Vector3(x, _heights.height_at(x, z), z)
	return null


## Tree variants: [seed, height, style]. Each placed tree picks one by biome, then gets its
## own scale, rotation and needle tint so the forest doesn't repeat.
const TREE_VARIANTS := [
	[11, 9.0, "fir"], [23, 11.0, "fir"], [37, 13.0, "fir"],
	[41, 14.0, "spruce"], [53, 11.5, "spruce"],
	[61, 13.5, "pine"], [67, 11.0, "pine"],
	[71, 3.5, "sapling"], [79, 5.0, "sapling"],
	[83, 8.0, "dead"],
]
## Limits so no placed tree gets silly: per-tree scale range, and a hard cap on final height.
const TREE_SCALE := Vector2(0.8, 1.2)
const TREE_MAX_HEIGHT := 15.0


## Deep forest is firs and spruces; edges and meadows lean to pines and young trees; dead
## snags are rare.
func _pick_variant(forest: float) -> int:
	var roll := _rng.randf()
	if roll < 0.015:
		return 9
	var style_roll := _rng.randf()
	if style_roll < 0.25 * (1.0 - forest) + 0.08:
		return _rng.randi_range(7, 8)
	if style_roll < 0.6 * (1.0 - forest) + 0.15:
		return _rng.randi_range(5, 6)
	return _rng.randi_range(0, 4)


func _place_trees(count: int, cfg: Dictionary, collision: StaticBody3D) -> void:
	var transforms: Array = []
	var colours: Array = []
	for v in TREE_VARIANTS:
		transforms.append([])
		colours.append([])
	# Dense in forests, the odd lone tree out in the meadows, none on bare rock.
	var tree_weight := func(x: float, z: float) -> float:
		# Squared so only forest cores are dense; most woodland is open enough to see through.
		return maxf(pow(_biomes.forest(x, z), 2.0), 0.015) * (1.0 - _biomes.rock(x, z) * 0.8)
	for i in count:
		var spot: Variant = _random_spot(cfg, tree_weight)
		if not spot is Vector3:
			continue
		var at: Vector3 = spot
		var variant := _pick_variant(_biomes.forest(at.x, at.z))
		var height: float = TREE_VARIANTS[variant][1]
		var scale := minf(_rng.randf_range(TREE_SCALE.x, TREE_SCALE.y), TREE_MAX_HEIGHT / height)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * scale)
		transforms[variant].append(Transform3D(basis, at + Vector3.DOWN * 0.1))
		# Needle tint stays close to white: the texture carries the colour, this only varies it.
		colours[variant].append(Color(0.85, 0.9, 0.85).lerp(Color(1.05, 1.0, 0.85), _rng.randf()))
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = height * 0.02 * scale
		cyl.height = height * scale * 0.6
		shape.shape = cyl
		shape.position = at + Vector3.UP * cyl.height * 0.5
		collision.add_child(shape)
	if _visual:
		for v in TREE_VARIANTS.size():
			if (transforms[v] as Array).is_empty():
				continue
			var spec: Array = TREE_VARIANTS[v]
			var mesh := PineTreeMesh.build(spec[0], spec[1], spec[2])
			var inst := _multimesh("Trees_%s_%d" % [spec[2], v], mesh, _typed(transforms[v]), _typed_colours(colours[v]))
			inst.visibility_range_end = 220.0


func _typed(a: Array) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.assign(a)
	return out


func _typed_colours(a: Array) -> Array[Color]:
	var out: Array[Color] = []
	out.assign(a)
	return out


func _place_rocks(count: int, cfg: Dictionary, collision: StaticBody3D) -> void:
	var transforms: Array[Transform3D] = []
	var colours: Array[Color] = []
	var rock_mesh := _rock_mesh()
	var rock_points := _unique_points(rock_mesh)
	# Boulder fields on rocky ground, a few stones scattered elsewhere.
	var rock_weight := func(x: float, z: float) -> float:
		return 0.05 + _biomes.rock(x, z) * 0.95
	for i in count:
		var spot: Variant = _random_spot(cfg, rock_weight)
		if not spot is Vector3:
			continue
		var at: Vector3 = spot
		# Rocky ground gets the big boulders.
		var size := _rng.randf_range(0.4, 1.2) + _biomes.rock(at.x, at.z) * _rng.randf_range(0.0, 1.6)
		var basis := Basis.from_euler(Vector3(_rng.randf() * 0.4, _rng.randf() * TAU, _rng.randf() * 0.4)).scaled(Vector3(size, size * _rng.randf_range(0.5, 0.9), size))
		transforms.append(Transform3D(basis, at + Vector3.DOWN * size * 0.15))
		var grey := _rng.randf_range(0.38, 0.52)
		colours.append(Color(grey, grey * 0.98, grey * 0.95) * 2.0)
		# Collision is the rock's own hull, so nobody bumps into or stands on air over it.
		# Stones lower than a step get none: you walk over them.
		var hull := PackedVector3Array()
		var top := -INF
		for point in rock_points:
			var p := basis * point
			hull.append(p)
			top = maxf(top, p.y)
		var rock_at := at + Vector3.DOWN * size * 0.15
		if rock_at.y + top - at.y < STEP_OVER_HEIGHT:
			continue
		var shape := CollisionShape3D.new()
		var convex := ConvexPolygonShape3D.new()
		convex.points = hull
		shape.shape = convex
		shape.position = rock_at
		collision.add_child(shape)
	if _visual:
		_multimesh("Rocks", rock_mesh, transforms, colours)


func _place_grass(count: int, cfg: Dictionary) -> void:
	var transforms: Array[Transform3D] = []
	var colours: Array[Color] = []
	var half := _heights.size / 2.0 - 2.0
	for i in count:
		var x := _rng.randf_range(-half, half)
		var z := _rng.randf_range(-half, half)
		# Thick in meadows, thin on the forest floor and on rock.
		var keep := 1.0 - _biomes.forest(x, z) * 0.8 - _biomes.rock(x, z) * 0.6
		if _rng.randf() > keep:
			continue
		var s := _rng.randf_range(0.5, 1.1)
		transforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.7, 1.4), s)), Vector3(x, _heights.height_at(x, z), z)))
		var green := Color(0.3, 0.36, 0.18).lerp(Color(0.44, 0.45, 0.25), _rng.randf())
		colours.append(green.lerp(Color(0.62, 0.55, 0.32), _biomes.dry(x, z) * 0.85))
	var mm := _multimesh("Grass", _grass_mesh(), transforms, colours)
	_grass = mm.multimesh
	for i in transforms.size():
		var cell := _grass_cell(transforms[i].origin)
		if not _grass_cells.has(cell):
			_grass_cells[cell] = PackedInt32Array()
		_grass_cells[cell].append(i)
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Grass far away is noise; fade it out with distance to keep the horizon clean.
	mm.visibility_range_end = 70.0
	mm.visibility_range_end_margin = 10.0
	mm.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _grass_cell(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x / GRASS_CELL), floori(at.z / GRASS_CELL))


## Removes the grass a dug sphere took the ground out from under, so it doesn't float.
func clear_grass(center: Vector3, radius: float) -> void:
	if _grass == null:
		return
	var reach := radius + GRASS_CLEAR_MARGIN
	var low := _grass_cell(center - Vector3.ONE * reach)
	var high := _grass_cell(center + Vector3.ONE * reach)
	for cx in range(low.x, high.x + 1):
		for cz in range(low.y, high.y + 1):
			var cell := Vector2i(cx, cz)
			if not _grass_cells.has(cell):
				continue
			var keep := PackedInt32Array()
			for i in _grass_cells[cell]:
				if _grass.get_instance_transform(i).origin.distance_to(center) < radius + GRASS_CLEAR_MARGIN:
					# A zero basis draws nothing; MultiMesh has no way to drop one instance.
					_grass.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), center))
				else:
					keep.append(i)
			_grass_cells[cell] = keep


func _multimesh(node_name: String, mesh: Mesh, transforms: Array[Transform3D], colours: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colours.is_empty()
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colours[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = node_name
	inst.multimesh = mm
	add_child(inst)
	return inst


func _material(colour: Color, use_instance_colour: bool, double_sided: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.9
	mat.vertex_color_use_as_albedo = use_instance_colour
	# Instance tints are picked in sRGB; read as linear they wash out to near white.
	mat.vertex_color_is_srgb = true
	if double_sided:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _trunk_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.12
	m.bottom_radius = 0.2
	m.height = 2.0
	m.radial_segments = 6
	m.rings = 1
	m.material = _material(Color(0.22, 0.19, 0.16), false)
	# CylinderMesh is centred; lift it so the base sits on the ground.
	var st := SurfaceTool.new()
	st.append_from(m, 0, Transform3D(Basis.IDENTITY, Vector3.UP * 1.0))
	var out := st.commit()
	out.surface_set_material(0, m.material)
	return out


func _canopy_mesh() -> Mesh:
	# Fir: four drooping tiers whose rim alternates in and out, so the silhouette reads as
	# branches instead of a smooth toy cone. Each tier is twisted differently.
	var st := LowPoly.begin()
	var tiers := [[1.5, 1.5, 0.0], [1.2, 1.4, 0.9], [0.9, 1.25, 1.75], [0.55, 1.1, 2.5]]
	var twist := 0.0
	for tier: Array in tiers:
		var radius: float = tier[0]
		var height: float = tier[1]
		var base_y: float = tier[2]
		var sides := 10
		var apex := Vector3(0, base_y + height, 0)
		for i in sides:
			var a0 := twist + TAU * float(i) / sides
			var a1 := twist + TAU * float(i + 1) / sides
			# Every other rim point juts out and hangs lower: branch tips.
			var r0 := radius * (1.0 if i % 2 == 0 else 0.72)
			var r1 := radius * (1.0 if (i + 1) % 2 == 0 else 0.72)
			var d0 := 0.18 if i % 2 == 0 else 0.0
			var d1 := 0.18 if (i + 1) % 2 == 0 else 0.0
			var p0 := Vector3(cos(a0) * r0, base_y - d0, sin(a0) * r0)
			var p1 := Vector3(cos(a1) * r1, base_y - d1, sin(a1) * r1)
			# Outer face points away from a spot on the trunk inside the tier.
			_canopy_tri(st, apex, p1, p0, Vector3(0, base_y + height * 0.3, 0))
			# Underside so the tier isn't hollow when seen from below; faces downward.
			_canopy_tri(st, Vector3(0, base_y + 0.15, 0), p0, p1, Vector3(0, base_y + 1.0, 0))
		twist += 0.45
	st.generate_normals()
	var out := st.commit()
	out.surface_set_material(0, _material(Color.WHITE, true))
	return out


## Canopy triangle facing away from `inside`. Winding is fixed here rather than by vertex
## order, which is easy to get wrong and renders inverted faces black. White vertex colour,
## so the instance colour alone tints the tree.
func _canopy_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var n := (b - a).cross(c - a)
	# Godot's front faces wind clockwise, so a front face's cross product points inward.
	if n.dot((a + b + c) / 3.0 - inside) > 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_color(Color.WHITE)
		st.add_vertex(v)


func _unique_points(mesh: Mesh) -> PackedVector3Array:
	var seen: Dictionary[Vector3, bool] = {}
	for v: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		seen[v.snappedf(0.0001)] = true
	return PackedVector3Array(seen.keys())


func _rock_mesh() -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 6
	sphere.rings = 3
	var st := SurfaceTool.new()
	st.append_from(sphere, 0, Transform3D.IDENTITY)
	# Faceted rocks: de-indexing gives each face its own vertices, so generated normals are
	# flat. (generate_normals' argument flips normals inward; it is not "flat shading".)
	st.deindex()
	st.generate_normals()
	var out := st.commit()
	# Same CC0 rock as the cliffs, tinted per instance so no two rocks match exactly. The
	# server only needs the shape for collision.
	if _visual:
		out.surface_set_material(0, WorldMaterials.triplanar("Rock030", Color.WHITE, 1.5, true))
	return out


func _grass_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	# A tuft of five thin blades fanned around the centre. Each blade is written with both
	# windings and an up normal, instead of disabling culling: Godot flips the normal on
	# back faces, which lights them from below and turns half the grass black.
	for i in 5:
		var angle := TAU * float(i) / 5.0
		var side := Vector3(cos(angle), 0.0, sin(angle)) * 0.06
		var lean := Vector3(cos(angle + 0.6), 0.0, sin(angle + 0.6)) * 0.12
		var tip := Vector3.UP * 0.35 + lean
		for tri in [[-side, side, tip], [side, -side, tip]]:
			for v: Vector3 in tri:
				st.add_vertex(v)
	var out := st.commit()
	var wind := ShaderMaterial.new()
	wind.shader = load("res://modules/world/shaders/grass.gdshader")
	out.surface_set_material(0, wind)
	return out

class_name VoxBoltRifle
extends VoxGenerator
## A bolt-action rifle in parts: a round receiver with scope bases and a trigger guard, a
## long tapered barrel with a front post, a one-piece stock (forend, semi-pistol wrist,
## butt with a rubber pad), the bolt with its handle and knob, a short box magazine, and a
## long scope with a wide objective bell and turrets. Real-world metres.
##
## Every part is drawn in gun space (the receiver's origin, the barrel pointing down -Z, y
## up), so "Whole rifle" is just all of them. `part_mesh` cuts one part out and moves it so
## its origin is its mount on the receiver, which is how the weapons module hangs parts on
## each other; `MOUNTS` must match the receiver's `mounts` in the weapons data.

const PARTS: Array[String] = ["Whole rifle", "Receiver", "Barrel", "Stock", "Bolt", "Magazine", "Scope"]
## `part_mesh` names, in the order of PARTS after the whole rifle.
const PART_KEYS: Array[String] = ["receiver", "barrel", "stock", "bolt", "magazine", "scope"]
const FINISHES: Array[String] = ["Walnut", "Beech", "Olive polymer"]
const WOOD := [Color(0.4, 0.25, 0.14), Color(0.6, 0.45, 0.28), Color(0.3, 0.33, 0.24)]
const BLUED := Color(0.16, 0.17, 0.19)
const DARK := Color(0.07, 0.07, 0.08)
const RUBBER := Color(0.06, 0.06, 0.06)
const LENS := Color(0.12, 0.2, 0.3)

## Height of the bore above the receiver's origin.
const BORE := 0.03
## Where each part's origin sits in gun space: its mount point on the receiver.
const MOUNTS := {
	"receiver": Vector3.ZERO,
	"barrel": Vector3(0.0, BORE, -0.115),
	"stock": Vector3.ZERO,
	"bolt": Vector3(0.0, BORE, 0.07),
	"magazine": Vector3(0.0, 0.01, -0.04),
	"scope": Vector3(0.0, 0.056, -0.02),
}
## Barrel length from its mount to the muzzle.
const BARREL_LENGTH := 0.62
## The scope's axis above its mount, and its eyepiece's rear face (scope space).
const SCOPE_AXIS := 0.04
const SCOPE_EYEPIECE_Z := 0.14
## Each part's box in gun space (the whole rifle's under ""): its grid is fitted to it, so the
## part stands on the ground and fills the asset library's view. Grids are centred on x.
const BOUNDS := {
	"": AABB(Vector3(-0.07, -0.115, -0.75), Vector3(0.14, 0.245, 1.17)),
	"receiver": AABB(Vector3(-0.03, -0.05, -0.12), Vector3(0.06, 0.11, 0.21)),
	"barrel": AABB(Vector3(-0.02, 0.012, -0.75), Vector3(0.04, 0.045, 0.65)),
	"stock": AABB(Vector3(-0.03, -0.115, -0.37), Vector3(0.06, 0.155, 0.79)),
	"bolt": AABB(Vector3(-0.07, 0.0, 0.055), Vector3(0.14, 0.06, 0.075)),
	"magazine": AABB(Vector3(-0.02, -0.06, -0.08), Vector3(0.04, 0.075, 0.08)),
	"scope": AABB(Vector3(-0.04, 0.05, -0.235), Vector3(0.08, 0.08, 0.36)),
}

## Gun space to model space for the part being built.
var _offset := Vector3.ZERO


func title() -> String:
	return "Bolt-action rifle"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		choice("part", "Part", PARTS, 0),
		choice("finish", "Stock", FINISHES, 0),
		voxel_param(0.004, 0.01, 0.005),
	]


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var m := new_model()
	var part := clampi(int(p["part"]), 0, PART_KEYS.size())
	var v := float(p["voxel"])
	var box: AABB = BOUNDS["" if part == 0 else PART_KEYS[part - 1]]
	box = box.grow(v * 2.0)
	var half_x := maxf(absf(box.position.x), absf(box.end.x))
	m.setup(Vector3(half_x * 2.0, box.size.y, box.size.z), v)
	# The grid's x and z are centred and its y starts at 0.
	_offset = Vector3(0.0, -box.position.y, -box.get_center().z)
	var wood: Color = WOOD[clampi(int(p["finish"]), 0, WOOD.size() - 1)]
	# Wood first: the metal parts sit in the stock and overwrite where they overlap.
	if part == 0 or part == 3:
		_stock(m, wood, seed)
	if part == 0 or part == 2:
		_barrel(m, seed)
	if part == 0 or part == 1:
		_receiver(m, seed)
	if part == 0 or part == 4:
		_bolt(m, seed)
	if part == 0 or part == 5:
		_magazine(m, seed)
	if part == 0 or part == 6:
		_scope(m, seed)
	return m


## One part as a mesh in its own space (origin at its mount), with the shared voxel
## material; null for an unknown part.
static func part_mesh(part: String) -> ArrayMesh:
	var index := PART_KEYS.find(part)
	if index < 0:
		return null
	VoxShading.ensure()
	var gen := VoxBoltRifle.new()
	var arrays := gen.build({"part": float(index + 1)}).mesh_arrays()
	var mesh := ArrayMesh.new()
	if arrays.is_empty():
		return mesh
	var to_part := -gen._offset - (MOUNTS[part] as Vector3)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] += to_part
	arrays[Mesh.ARRAY_VERTEX] = verts
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material())
	return mesh


func _g(at: Vector3) -> Vector3:
	return at + _offset


func _box(m: VoxelModel, lo: Vector3, hi: Vector3, colour: Color, jitter: float, seed: int) -> void:
	m.fill_box(_g(lo), _g(hi), colour, jitter, seed)


## A round tube along Z from `z_back` to `z_front` (z_front < z_back), radii tapering from
## back to front, with flat ends.
func _tube(m: VoxelModel, axis: Vector3, z_back: float, z_front: float, r_back: float, r_front: float, colour: Color, seed: int, flat_back := true, flat_front := true) -> void:
	var a := Vector3(axis.x, axis.y, z_back)
	var b := Vector3(axis.x, axis.y, z_front)
	m.fill_capsule(_g(a), _g(b), r_back, r_front, colour, 0.0, seed)
	var r := maxf(r_back, r_front) + 0.002
	if flat_back:
		m.carve_box(_g(Vector3(axis.x - r, axis.y - r, z_back)), _g(Vector3(axis.x + r, axis.y + r, z_back + r)))
	if flat_front:
		m.carve_box(_g(Vector3(axis.x - r, axis.y - r, z_front - r)), _g(Vector3(axis.x + r, axis.y + r, z_front)))


## Round receiver on a flat bottom, ejection port on the right, rear sight notch, two
## scope bases and the trigger with its guard underneath.
func _receiver(m: VoxelModel, seed: int) -> void:
	var b := BORE
	m.fill_capsule(_g(Vector3(0.0, b, -0.1)), _g(Vector3(0.0, b, 0.08)), 0.015, 0.015, BLUED, 0.0, seed)
	_box(m, Vector3(-0.014, b - 0.022, -0.112), Vector3(0.014, b, 0.092), BLUED, 0.0, seed)
	# Ejection port: a notch on the right with the dark bolt body showing in it.
	m.carve_box(_g(Vector3(0.009, b - 0.004, -0.045)), _g(Vector3(0.02, b + 0.012, 0.015)))
	m.paint_box(_g(Vector3(0.0, b - 0.006, -0.046)), _g(Vector3(0.011, b + 0.014, 0.016)), DARK, 0.0, seed)
	# Rear sight with its notch.
	_box(m, Vector3(-0.008, b + 0.013, 0.07), Vector3(0.008, b + 0.024, 0.082), DARK, 0.0, seed)
	m.carve_box(_g(Vector3(-0.0025, b + 0.019, 0.068)), _g(Vector3(0.0025, b + 0.026, 0.084)))
	# Scope bases, their tops at the optic mount.
	var top: float = (MOUNTS["scope"] as Vector3).y
	for z: float in [-0.09, 0.012]:
		_box(m, Vector3(-0.009, b + 0.01, z), Vector3(0.009, top, z + 0.018), DARK, 0.0, seed)
	# Trigger guard (a loop under the stock) and the trigger blade inside it.
	_box(m, Vector3(-0.005, -0.046, 0.0), Vector3(0.005, -0.04, 0.075), BLUED, 0.0, seed)
	_box(m, Vector3(-0.005, -0.046, 0.0), Vector3(0.005, b - 0.02, 0.007), BLUED, 0.0, seed)
	_box(m, Vector3(-0.005, -0.046, 0.068), Vector3(0.005, b - 0.02, 0.075), BLUED, 0.0, seed)
	_box(m, Vector3(-0.003, -0.032, 0.032), Vector3(0.003, b - 0.02, 0.039), DARK, 0.0, seed)


## Tapered barrel with a front sight post and a dark crown.
func _barrel(m: VoxelModel, seed: int) -> void:
	var mount: Vector3 = MOUNTS["barrel"]
	var front := mount.z - BARREL_LENGTH
	_tube(m, mount, mount.z, front, 0.0115, 0.0085, BLUED, seed, false)
	_box(m, Vector3(-0.009, mount.y - 0.009, front + 0.018), Vector3(0.009, mount.y + 0.011, front + 0.03), BLUED, 0.0, seed)
	_box(m, Vector3(-0.0025, mount.y + 0.008, front + 0.02), Vector3(0.0025, mount.y + 0.022, front + 0.026), DARK, 0.0, seed)
	m.paint_box(_g(Vector3(-0.004, mount.y - 0.004, front - 0.002)), _g(Vector3(0.004, mount.y + 0.004, front + 0.004)), DARK, 0.0, seed)


## One-piece stock: forend under the barrel, the bed the receiver sits in, a semi-pistol
## wrist for the firing hand, a butt that drops toward the shoulder, and a rubber pad.
func _stock(m: VoxelModel, wood: Color, seed: int) -> void:
	_box(m, Vector3(-0.021, -0.024, -0.34), Vector3(0.021, 0.024, -0.1), wood, 0.0, seed)
	m.fill_ellipsoid(_g(Vector3(0.0, 0.0, -0.34)), Vector3(0.021, 0.024, 0.02), wood, 0.0, seed)
	_box(m, Vector3(-0.022, -0.04, -0.12), Vector3(0.022, 0.022, 0.09), wood, 0.0, seed)
	# Sling stud under the forend.
	_box(m, Vector3(-0.003, -0.032, -0.31), Vector3(0.003, -0.024, -0.3), DARK, 0.0, seed)
	m.fill_capsule(_g(Vector3(0.0, -0.012, 0.075)), _g(Vector3(0.0, -0.088, 0.122)), 0.017, 0.019, wood, 0.0, seed)
	# Butt: a slice per voxel, the comb rising slightly and the toe dropping toward the pad.
	var step := m.voxel_size()
	var z := 0.09
	while z < 0.4:
		var t := (z - 0.09) / 0.31
		var top := lerpf(0.02, 0.032, t)
		var bottom := lerpf(-0.045, -0.105, sqrt(t))
		_box(m, Vector3(-0.019, bottom, z), Vector3(0.019, top, z + step), wood, 0.0, seed)
		z += step
	_box(m, Vector3(-0.02, -0.107, 0.4), Vector3(0.02, 0.034, 0.415), RUBBER, 0.0, seed)
	# Grain: long bands of lighter and darker wood along the stock. Per-voxel noise would
	# split every face into single voxels and cost ten times the triangles.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var y := -0.11
	while y < 0.035:
		var band := step * float(rng.randi_range(1, 3))
		var z0 := rng.randf_range(-0.36, 0.1)
		var k := rng.randf_range(0.9, 1.08)
		m.paint_box(_g(Vector3(-0.03, y, z0)), _g(Vector3(0.03, y + band, rng.randf_range(z0 + 0.12, 0.4))), Color(wood.r * k, wood.g * k, wood.b * k), 0.0, seed)
		y += band * 2.0
	# Checkering where the hands go: the forend's sides and the wrist.
	var dark := wood.darkened(0.3)
	for area: AABB in [AABB(Vector3(-0.03, -0.018, -0.3), Vector3(0.06, 0.03, 0.1)), AABB(Vector3(-0.03, -0.06, 0.085), Vector3(0.06, 0.04, 0.03))]:
		var cz := area.position.z
		var row := 0
		while cz < area.end.z:
			var cy := area.position.y + step * float(row % 2)
			while cy < area.end.y:
				m.paint_box(_g(Vector3(area.position.x, cy, cz)), _g(Vector3(area.end.x, cy + step, cz + step)), dark, 0.0, seed)
				cy += step * 2.0
			cz += step
			row += 1

## The bolt: its shroud behind the receiver and the handle out to the right, bent down,
## ending in a round knob. Drawn around its mount, which sits on the bore so the handle
## turns up around it.
func _bolt(m: VoxelModel, seed: int) -> void:
	var o: Vector3 = MOUNTS["bolt"]
	m.fill_capsule(_g(o + Vector3(0.0, 0.0, 0.01)), _g(o + Vector3(0.0, 0.0, 0.05)), 0.011, 0.01, BLUED, 0.0, seed)
	m.fill_capsule(_g(o + Vector3(0.01, 0.0, 0.0)), _g(o + Vector3(0.042, -0.012, 0.006)), 0.0045, 0.004, BLUED, 0.0, seed)
	m.fill_ellipsoid(_g(o + knob()), Vector3(0.009, 0.009, 0.009), DARK, 0.0, seed)


## Where the bolt knob sits in bolt space, for the hand that works it.
static func knob() -> Vector3:
	return Vector3(0.05, -0.016, 0.008)


## A short box magazine with a darker floorplate.
func _magazine(m: VoxelModel, seed: int) -> void:
	var o: Vector3 = MOUNTS["magazine"]
	_box(m, o + Vector3(-0.011, -0.062, -0.03), o + Vector3(0.011, 0.0, 0.03), BLUED, 0.0, seed)
	_box(m, o + Vector3(-0.013, -0.068, -0.033), o + Vector3(0.013, -0.06, 0.033), DARK, 0.0, seed)


## Long scope: main tube, a cone out to a wide objective bell, an eyepiece, elevation and
## windage turrets, two rings down to the mount, and dark glass at both ends.
func _scope(m: VoxelModel, seed: int) -> void:
	var o: Vector3 = MOUNTS["scope"]
	var axis := o + Vector3(0.0, SCOPE_AXIS, 0.0)
	_tube(m, axis, o.z + 0.1, o.z - 0.13, 0.0125, 0.0125, BLUED, seed, false, false)
	_tube(m, axis, o.z - 0.13, o.z - 0.165, 0.0125, 0.022, BLUED, seed, false, false)
	_tube(m, axis, o.z - 0.165, o.z - 0.205, 0.022, 0.022, BLUED, seed, false, true)
	_tube(m, axis, o.z + 0.1, o.z + 0.115, 0.0125, 0.019, BLUED, seed, false, false)
	_tube(m, axis, o.z + SCOPE_EYEPIECE_Z, o.z + 0.115, 0.019, 0.019, RUBBER, seed, true, false)
	# Glass: a recess in each end with its floor tinted.
	m.paint_ellipsoid(_g(axis + Vector3(0.0, 0.0, -0.198)), Vector3(0.017, 0.017, 0.006), LENS, 0.0, seed)
	m.carve_ellipsoid(_g(axis + Vector3(0.0, 0.0, -0.207)), Vector3(0.017, 0.017, 0.006))
	m.paint_ellipsoid(_g(axis + Vector3(0.0, 0.0, SCOPE_EYEPIECE_Z - 0.006)), Vector3(0.014, 0.014, 0.006), LENS, 0.0, seed)
	m.carve_ellipsoid(_g(axis + Vector3(0.0, 0.0, SCOPE_EYEPIECE_Z + 0.002)), Vector3(0.014, 0.014, 0.006))
	# Turrets: elevation on top, windage on the right, with darker caps.
	_box(m, axis + Vector3(-0.009, 0.01, -0.019), axis + Vector3(0.009, 0.026, -0.001), BLUED, 0.0, seed)
	_box(m, axis + Vector3(-0.0095, 0.022, -0.0195), axis + Vector3(0.0095, 0.028, -0.0005), DARK, 0.0, seed)
	_box(m, axis + Vector3(0.01, -0.009, -0.019), axis + Vector3(0.026, 0.009, -0.001), BLUED, 0.0, seed)
	_box(m, axis + Vector3(0.022, -0.0095, -0.0195), axis + Vector3(0.028, 0.0095, -0.0005), DARK, 0.0, seed)
	# Rings round the tube and down to the bases.
	for z: float in [-0.07, 0.032]:
		_box(m, Vector3(-0.016, axis.y - 0.016, o.z + z), Vector3(0.016, axis.y + 0.016, o.z + z + 0.014), DARK, 0.0, seed)
		_box(m, Vector3(-0.009, o.y, o.z + z), Vector3(0.009, axis.y - 0.014, o.z + z + 0.014), DARK, 0.0, seed)

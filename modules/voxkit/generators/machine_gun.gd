class_name VoxMachineGun
extends VoxGenerator
## A belt-fed machine gun in parts: a boxy receiver with a hinged feed cover, the rear sight
## and a pistol grip, a heavy barrel with a gas tube, a carry handle off to the left side
## (clear of the sight line), a front post and a slotted flash hider, a fixed stock, a bipod
## with its legs folded forward under the barrel, and a box for the belt on the left with
## a few rounds running up into the feed tray. Real-world metres.
##
## Drawn the same way as `VoxBoltRifle`: every part in gun space (the receiver's origin, the
## barrel down -Z, y up), so "Whole gun" is all of them, and `part_mesh` cuts one part out
## around its mount; `MOUNTS` must match the receiver's `mounts` in the weapons data.

const PARTS: Array[String] = ["Whole gun", "Receiver", "Barrel", "Stock", "Bipod", "Belt box"]
## `part_mesh` names, in the order of PARTS after the whole gun.
const PART_KEYS: Array[String] = ["receiver", "barrel", "stock", "bipod", "belt"]
const FINISHES: Array[String] = ["Olive", "Black", "Sand"]
const FURNITURE := [Color(0.2, 0.23, 0.15), Color(0.11, 0.11, 0.12), Color(0.45, 0.4, 0.29)]
const GUNMETAL := Color(0.17, 0.18, 0.19)
const BLUED := Color(0.13, 0.14, 0.16)
const DARK := Color(0.06, 0.06, 0.07)
const BRASS := Color(0.7, 0.55, 0.26)
## The belt box stays army green whatever the furniture: it is issued, not part of the gun.
const CAN := Color(0.3, 0.34, 0.22)

## Height of the bore above the receiver's origin.
const BORE := 0.035
## Height of the line from the rear sight's notch over the front post: tall sights, so the
## eye sits well clear of the feed cover and the stock when aiming.
const SIGHT_LINE := 0.1
## Where each part's origin sits in gun space: its mount point on the receiver.
const MOUNTS := {
	"receiver": Vector3.ZERO,
	"barrel": Vector3(0.0, BORE, -0.17),
	"stock": Vector3(0.0, 0.02, 0.125),
	"bipod": Vector3(0.0, BORE - 0.02, -0.42),
	"belt": Vector3(-0.03, 0.0, -0.06),
}
## Barrel length from its mount to the muzzle, flash hider included.
const BARREL_LENGTH := 0.56
const FLASH_HIDER := 0.07
## Where the support hand holds the carry handle and the firing hand the grip, gun space.
const HANDLE := Vector3(-0.04, BORE - 0.035, -0.22)
const GRIP := Vector3(0.0, -0.068, 0.117)
## Each part's box in gun space (the whole gun's under ""): its grid is fitted to it, so the
## part stands on the ground and fills the asset library's view. Grids are centred on x.
const BOUNDS := {
	"": AABB(Vector3(-0.1, -0.125, -0.745), Vector3(0.14, 0.24, 1.19)),
	"receiver": AABB(Vector3(-0.04, -0.125, -0.18), Vector3(0.08, 0.235, 0.33)),
	"barrel": AABB(Vector3(-0.06, BORE - 0.05, -0.745), Vector3(0.08, 0.12, 0.59)),
	"stock": AABB(Vector3(-0.03, -0.09, 0.115), Vector3(0.06, 0.15, 0.33)),
	"bipod": AABB(Vector3(-0.03, BORE - 0.05, -0.7), Vector3(0.06, 0.07, 0.3)),
	"belt": AABB(Vector3(-0.095, -0.115, -0.125), Vector3(0.075, 0.18, 0.13)),
}

## Gun space to model space for the part being built.
var _offset := Vector3.ZERO


func title() -> String:
	return "Machine gun"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		choice("part", "Part", PARTS, 0),
		choice("finish", "Furniture", FINISHES, 0),
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
	var furniture: Color = FURNITURE[clampi(int(p["finish"]), 0, FURNITURE.size() - 1)]
	if part == 0 or part == 3:
		_stock(m, furniture, seed)
	if part == 0 or part == 2:
		_barrel(m, furniture, seed)
	if part == 0 or part == 4:
		_bipod(m, seed)
	if part == 0 or part == 1:
		_receiver(m, furniture, seed)
	if part == 0 or part == 5:
		_belt(m, seed)
	return m


## One part as a mesh in its own space (origin at its mount), with the shared voxel
## material; null for an unknown part.
static func part_mesh(part: String) -> ArrayMesh:
	var index := PART_KEYS.find(part)
	if index < 0:
		return null
	VoxShading.ensure()
	var gen := VoxMachineGun.new()
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


func _box(m: VoxelModel, lo: Vector3, hi: Vector3, colour: Color, seed: int) -> void:
	m.fill_box(_g(lo), _g(hi), colour, 0.0, seed)


## A round tube along Z from `z_back` to `z_front` (z_front < z_back) with flat ends.
## `flat_front` false leaves the front end round, to tuck into whatever is drawn there.
func _tube(m: VoxelModel, axis: Vector3, z_back: float, z_front: float, radius: float, colour: Color, seed: int, flat_front := true) -> void:
	m.fill_capsule(_g(Vector3(axis.x, axis.y, z_back)), _g(Vector3(axis.x, axis.y, z_front)), radius, radius, colour, 0.0, seed)
	var r := radius + 0.002
	m.carve_box(_g(Vector3(axis.x - r, axis.y - r, z_back)), _g(Vector3(axis.x + r, axis.y + r, z_back + r)))
	if flat_front:
		m.carve_box(_g(Vector3(axis.x - r, axis.y - r, z_front - r)), _g(Vector3(axis.x + r, axis.y + r, z_front)))


## A boxy receiver with the barrel's trunnion collar at the front, the feed cover on top
## (hinged at the front, latched at the back), the rear sight behind it, the feed tray's
## opening on the left where the belt comes in, the charging handle on the right, and the
## trigger guard with a pistol grip underneath.
func _receiver(m: VoxelModel, furniture: Color, seed: int) -> void:
	var b := BORE
	_box(m, Vector3(-0.024, -0.02, -0.17), Vector3(0.024, b + 0.018, 0.125), GUNMETAL, seed)
	_box(m, Vector3(-0.027, -0.016, -0.18), Vector3(0.027, b + 0.02, -0.155), BLUED, seed)
	# Feed cover, a little wider than the receiver, with its hinge pin and latch.
	_box(m, Vector3(-0.026, b + 0.018, -0.13), Vector3(0.026, b + 0.029, 0.07), BLUED, seed)
	m.fill_capsule(_g(Vector3(-0.028, b + 0.022, -0.13)), _g(Vector3(0.028, b + 0.022, -0.13)), 0.005, 0.005, DARK, 0.0, seed)
	_box(m, Vector3(-0.01, b + 0.02, 0.07), Vector3(0.01, b + 0.033, 0.081), DARK, seed)
	# Rear sight: a thin leaf on a low base with a wide notch on the sight line. It is right in
	# front of the eye when aiming, so anything thicker hides the target.
	_box(m, Vector3(-0.01, b + 0.029, 0.084), Vector3(0.01, b + 0.036, 0.1), BLUED, seed)
	_box(m, Vector3(-0.01, b + 0.036, 0.09), Vector3(0.01, SIGHT_LINE + 0.006, 0.095), DARK, seed)
	m.carve_box(_g(Vector3(-0.0045, SIGHT_LINE - 0.001, 0.088)), _g(Vector3(0.0045, SIGHT_LINE + 0.01, 0.097)))
	# Feed tray opening on the left, ejection port under the right.
	m.paint_box(_g(Vector3(-0.026, b - 0.012, -0.085)), _g(Vector3(-0.02, b + 0.012, -0.03)), DARK, 0.0, seed)
	m.paint_box(_g(Vector3(0.02, -0.022, -0.07)), _g(Vector3(0.026, -0.006, -0.02)), DARK, 0.0, seed)
	# Charging handle.
	_box(m, Vector3(0.024, b - 0.006, -0.105), Vector3(0.038, b + 0.006, -0.088), DARK, seed)
	# Trigger guard, trigger, and the pistol grip behind them.
	_box(m, Vector3(-0.005, -0.048, 0.03), Vector3(0.005, -0.042, 0.097), BLUED, seed)
	_box(m, Vector3(-0.005, -0.048, 0.03), Vector3(0.005, -0.02, 0.037), BLUED, seed)
	_box(m, Vector3(-0.003, -0.036, 0.058), Vector3(0.003, -0.02, 0.065), DARK, seed)
	m.fill_capsule(_g(Vector3(0.0, -0.018, 0.099)), _g(Vector3(0.0, -0.106, 0.135)), 0.015, 0.016, furniture, 0.0, seed)
	# Finger grooves: darker bands across the front of the grip.
	for i in 3:
		var y := -0.04 - 0.02 * float(i)
		m.paint_box(_g(Vector3(-0.02, y, 0.085)), _g(Vector3(0.02, y + 0.005, 0.113 + 0.008 * float(i))), furniture.darkened(0.35), 0.0, seed)


## A heavy barrel: the tube with the gas tube under it, the gas block, a carry handle off to
## the left side (so it never blocks the sights), the front post on its block, and a long
## flash hider with slots and an open bore.
func _barrel(m: VoxelModel, furniture: Color, seed: int) -> void:
	var mount: Vector3 = MOUNTS["barrel"]
	var front := mount.z - BARREL_LENGTH
	var hider_back := front + FLASH_HIDER
	# Cooling rings and the flash hider go down first: the barrel's round front end then fills
	# into the hider, and flattening a short ring's ends can't cut into the barrel.
	for i in 4:
		var z := mount.z - 0.03 - 0.025 * float(i)
		_tube(m, mount, z, z - 0.008, 0.0155, GUNMETAL, seed)
	_tube(m, mount, hider_back, front, 0.0165, DARK, seed)
	_tube(m, mount, mount.z + 0.012, hider_back, 0.0135, BLUED, seed, false)
	# Gas tube under the barrel back to the receiver, and the gas block.
	var gas_y := mount.y - 0.024
	m.fill_capsule(_g(Vector3(0.0, gas_y, mount.z + 0.01)), _g(Vector3(0.0, gas_y, -0.47)), 0.007, 0.007, GUNMETAL, 0.0, seed)
	_box(m, Vector3(-0.016, gas_y - 0.01, -0.49), Vector3(0.016, mount.y + 0.014, -0.455), GUNMETAL, seed)
	# Carry handle, folded down on the left: a clamp round the barrel, two struts out to the
	# side and a grip along the barrel, where the support hand holds it.
	_box(m, Vector3(-0.018, mount.y - 0.016, HANDLE.z - 0.055), Vector3(0.018, mount.y + 0.016, HANDLE.z + 0.055), GUNMETAL, seed)
	for z: float in [HANDLE.z + 0.045, HANDLE.z - 0.045]:
		m.fill_capsule(_g(Vector3(-0.016, mount.y, z)), _g(Vector3(HANDLE.x + 0.004, HANDLE.y, z)), 0.005, 0.005, DARK, 0.0, seed)
	m.fill_capsule(_g(Vector3(HANDLE.x, HANDLE.y, HANDLE.z + 0.06)), _g(Vector3(HANDLE.x, HANDLE.y, HANDLE.z - 0.06)), 0.009, 0.009, furniture, 0.0, seed)
	# Front sight: a block round the barrel with a post up to the sight line.
	var post_z := hider_back + 0.03
	_box(m, Vector3(-0.012, mount.y - 0.012, post_z - 0.012), Vector3(0.012, mount.y + 0.03, post_z + 0.012), GUNMETAL, seed)
	# Ears either side of the post, so it reads as a sight from behind.
	for x: float in [-0.009, 0.006]:
		_box(m, Vector3(x, mount.y + 0.03, post_z - 0.005), Vector3(x + 0.003, SIGHT_LINE + 0.004, post_z + 0.005), GUNMETAL, seed)
	_box(m, Vector3(-0.0025, mount.y + 0.03, post_z - 0.004), Vector3(0.0025, SIGHT_LINE, post_z + 0.004), DARK, seed)
	# Flash hider: slotted on four sides, open at the front.
	var slot_front := front + 0.012
	var slot_back := hider_back - 0.015
	for lo: float in [-0.02, 0.01]:
		m.carve_box(_g(Vector3(-0.003, mount.y + lo, slot_front)), _g(Vector3(0.003, mount.y + lo + 0.01, slot_back)))
		m.carve_box(_g(Vector3(lo, mount.y - 0.003, slot_front)), _g(Vector3(lo + 0.01, mount.y + 0.003, slot_back)))
	m.carve_ellipsoid(_g(Vector3(0.0, mount.y, front)), Vector3(0.007, 0.007, 0.02))


## A fixed stock: a deep body from the receiver back to a dark butt plate, its underside
## dropping toward the shoulder, with a sling loop under the butt.
func _stock(m: VoxelModel, furniture: Color, seed: int) -> void:
	var o: Vector3 = MOUNTS["stock"]
	var step := m.voxel_size()
	var z := o.z
	while z < 0.4:
		var t := (z - o.z) / (0.4 - o.z)
		# Its top stays well under the sight line, so the cheek rests on it while aiming.
		var top := lerpf(0.04, 0.03, t)
		var bottom := lerpf(-0.012, -0.078, sqrt(t))
		var half := lerpf(0.021, 0.019, t)
		_box(m, Vector3(-half, bottom, z), Vector3(half, top, z + step), furniture, seed)
		z += step
	# A darker seam along each side where the two halves of the moulding meet.
	m.paint_box(_g(Vector3(-0.03, -0.02, o.z + 0.02)), _g(Vector3(0.03, -0.014, 0.4)), furniture.darkened(0.3), 0.0, seed)
	_box(m, Vector3(-0.022, -0.082, 0.4), Vector3(0.022, 0.034, 0.416), DARK, seed)
	_box(m, Vector3(-0.004, -0.088, 0.34), Vector3(0.004, -0.07, 0.37), DARK, seed)


## A bipod clamped round the barrel near the gas block, its two legs folded forward along
## the barrel with rubber feet just behind the flash hider.
func _bipod(m: VoxelModel, seed: int) -> void:
	var o: Vector3 = MOUNTS["bipod"]
	_box(m, Vector3(-0.018, o.y - 0.016, o.z - 0.014), Vector3(0.018, o.y + 0.02, o.z + 0.014), DARK, seed)
	# The yoke the legs hinge on, wider than the barrel.
	_box(m, Vector3(-0.024, o.y - 0.024, o.z - 0.01), Vector3(0.024, o.y - 0.012, o.z + 0.01), BLUED, seed)
	var feet_z := o.z - 0.24
	for x: float in [-0.017, 0.017]:
		m.fill_capsule(_g(Vector3(x, o.y - 0.018, o.z - 0.006)), _g(Vector3(x, o.y - 0.022, feet_z)), 0.0065, 0.006, BLUED, 0.0, seed)
		# A darker collar where each leg telescopes.
		m.paint_box(_g(Vector3(x - 0.008, o.y - 0.03, o.z - 0.12)), _g(Vector3(x + 0.008, o.y - 0.01, o.z - 0.105)), DARK, 0.0, seed)
		_box(m, Vector3(x - 0.008, o.y - 0.032, feet_z - 0.014), Vector3(x + 0.008, o.y - 0.012, feet_z + 0.004), DARK, seed)


## The belt box on the left of the receiver: an ammunition can with a darker lid and latch,
## and a short run of linked rounds climbing out of it into the feed tray.
func _belt(m: VoxelModel, seed: int) -> void:
	var o: Vector3 = MOUNTS["belt"]
	_box(m, o + Vector3(-0.058, -0.105, -0.055), o + Vector3(-0.002, -0.012, 0.055), CAN, seed)
	_box(m, o + Vector3(-0.06, -0.012, -0.057), o + Vector3(0.0, -0.004, 0.057), CAN.darkened(0.25), seed)
	_box(m, o + Vector3(-0.064, -0.03, -0.012), o + Vector3(-0.058, -0.008, 0.012), DARK, seed)
	# Stencilled band round the can.
	m.paint_box(_g(o + Vector3(-0.059, -0.07, -0.056)), _g(o + Vector3(-0.001, -0.064, 0.056)), CAN.lightened(0.2), 0.0, seed)
	# Rounds lie along the barrel, one above the next, stepping in toward the feed tray.
	var rounds := 5
	for i in rounds:
		var t := float(i) / float(rounds - 1)
		var at := Vector3(lerpf(-0.03, 0.006, t), lerpf(-0.004, BORE - 0.002, t), 0.0) + Vector3(o.x, 0.0, o.z)
		_box(m, at + Vector3(-0.005, 0.0, -0.022), at + Vector3(0.005, 0.009, 0.022), BRASS, seed)
		_box(m, at + Vector3(-0.004, 0.001, -0.03), at + Vector3(0.004, 0.008, -0.022), BRASS.darkened(0.45), seed)
		_box(m, at + Vector3(-0.006, 0.002, -0.006), at + Vector3(0.006, 0.007, 0.006), DARK, seed)

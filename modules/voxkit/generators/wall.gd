class_name VoxWall
extends VoxGenerator
## One free-standing wall on a concrete footing, in any building material: vertical planks,
## concrete poured in lifts, brick laid in mortar, ribbed sheet metal, or a glass pane in a
## wooden frame. Optionally a window (any glass) or a door gap. For the test range's samples.
## Runs along x, centred; its thickness runs along z, centred.

const KINDS: Array[String] = ["Planks", "Concrete", "Brick", "Sheet metal", "Window glass", "Tempered glass", "Laminated glass", "Security glass"]
## The voxel material behind each kind.
const KIND_MATERIALS: Array[String] = ["wood", "concrete", "brick", "sheet_metal", "window_glass", "tempered_glass", "laminated_glass", "security_glass"]
const WINDOWS: Array[String] = ["None", "Window glass", "Tempered glass", "Laminated glass", "Security glass"]
const WINDOW_MATERIALS: Array[String] = ["", "window_glass", "tempered_glass", "laminated_glass", "security_glass"]
const PLANK := Color(0.55, 0.17, 0.12)
const CAST := Color(0.56, 0.56, 0.53)
const METAL := Color(0.45, 0.47, 0.5)
const FRAME := Color(0.88, 0.86, 0.8)
const FOOTING := Color(0.58, 0.57, 0.54)
const GLASS := Color(0.55, 0.68, 0.75)
const FOOT := 0.15
const BOARD := 0.25
const LIFT := 0.6
const RIB := 0.2
## Window opening and its sill height, and the door gap, metres.
const WINDOW := Vector2(1.2, 0.8)
const SILL := 1.0
const DOOR := Vector2(1.0, 2.0)


func title() -> String:
	return "Wall sample"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		choice("kind", "Material", KINDS, 2),
		param("width", "Width (m)", 1.5, 8.0, 0.25, 4.0),
		param("height", "Height (m)", 1.5, 4.0, 0.1, 3.0),
		param("thickness", "Thickness (m)", 0.05, 0.5, 0.025, 0.225),
		choice("window", "Window", WINDOWS, 0),
		choice("door", "Door gap", ["No", "Yes"], 0),
		voxel_param(0.05, 0.2, 0.075),
	]


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["seed"])
	var seed := int(p["seed"])
	var w: float = p["width"]
	var h: float = p["height"]
	var t: float = p["thickness"]
	var v: float = p["voxel"]
	var kind := clampi(int(p["kind"]), 0, KINDS.size() - 1)
	var m := new_model()
	m.setup(Vector3(w + v * 4.0, h + v * 4.0, maxf(t, 0.3) + 0.4), v)
	m.set_material(VoxMaterials.index_of("concrete"))
	m.fill_box(Vector3(-w / 2.0 - 0.1, 0.0, -t / 2.0 - 0.1), Vector3(w / 2.0 + 0.1, FOOT, t / 2.0 + 0.1), FOOTING, 0.08, seed)
	var lo := Vector3(-w / 2.0, FOOT, -t / 2.0)
	var hi := Vector3(w / 2.0, h, t / 2.0)
	m.set_material(VoxMaterials.index_of(KIND_MATERIALS[kind]))
	match kind:
		0:
			var x := lo.x
			var board := 0
			while x < hi.x - 0.001:
				var x1 := minf(x + BOARD, hi.x)
				m.fill_box(Vector3(x, lo.y, lo.z), Vector3(x1, hi.y, hi.z), PLANK * rng.randf_range(0.86, 1.06), 0.07, seed + board)
				x = x1
				board += 1
		1:
			var y := lo.y
			var lift := 0
			while y < hi.y - 0.001:
				var y1 := minf(y + LIFT, hi.y)
				m.fill_box(Vector3(lo.x, y, lo.z), Vector3(hi.x, y1, hi.z), CAST * rng.randf_range(0.92, 1.04), 0.05, seed + lift)
				y = y1
				lift += 1
		2:
			m.set_material(VoxMaterials.index_of("mortar"))
			m.fill_box(lo, hi, VoxShed.MORTAR, 0.04, seed)
			_lay_bricks(m, lo, hi, v, rng, seed)
		3:
			var x := lo.x
			var rib := 0
			while x < hi.x - 0.001:
				var x1 := minf(x + RIB, hi.x)
				m.fill_box(Vector3(x, lo.y, lo.z), Vector3(x1, hi.y, hi.z), METAL if rib % 2 == 0 else METAL.darkened(0.12), 0.04, seed)
				x = x1
				rib += 1
		_:
			# A pane in a wooden frame.
			var frame := maxf(v * 2.0, 0.12)
			m.set_material(VoxMaterials.index_of("wood"))
			m.fill_box(lo, hi, FRAME, 0.03, seed)
			m.carve_box(lo + Vector3(frame, frame, -0.1), hi - Vector3(frame, frame, -0.1))
			m.set_material(VoxMaterials.index_of(KIND_MATERIALS[kind]))
			m.fill_box(Vector3(lo.x + frame, lo.y + frame, -v * 0.5), Vector3(hi.x - frame, hi.y - frame, v * 0.5), GLASS, 0.0, seed)
	if int(p["door"]) == 1 and kind < 4:
		var dx := -w / 4.0 if int(p["window"]) > 0 else 0.0
		m.carve_box(Vector3(dx - DOOR.x / 2.0, FOOT, lo.z - v), Vector3(dx + DOOR.x / 2.0, FOOT + DOOR.y, hi.z + v))
		m.set_material(VoxMaterials.index_of("wood"))
		m.fill_box(Vector3(dx - DOOR.x / 2.0 - v, FOOT + DOOR.y, lo.z - v), Vector3(dx + DOOR.x / 2.0 + v, FOOT + DOOR.y + v * 1.5, hi.z + v), FRAME, 0.04, seed)
	var window := clampi(int(p["window"]), 0, WINDOWS.size() - 1)
	if window > 0 and kind < 4:
		var wx := w / 4.0 if int(p["door"]) == 1 else 0.0
		var y0 := FOOT + SILL
		var frame := v * 1.5
		m.set_material(VoxMaterials.index_of("wood"))
		m.fill_box(Vector3(wx - WINDOW.x / 2.0 - frame, y0 - frame, lo.z - v), Vector3(wx + WINDOW.x / 2.0 + frame, y0 + WINDOW.y + frame, hi.z + v), FRAME, 0.04, seed)
		m.carve_box(Vector3(wx - WINDOW.x / 2.0, y0, lo.z - v * 2.0), Vector3(wx + WINDOW.x / 2.0, y0 + WINDOW.y, hi.z + v * 2.0))
		m.set_material(VoxMaterials.index_of(WINDOW_MATERIALS[window]))
		m.fill_box(Vector3(wx - WINDOW.x / 2.0, y0, -v * 0.5), Vector3(wx + WINDOW.x / 2.0, y0 + WINDOW.y, v * 0.5), GLASS, 0.0, seed)
	return m


## Bricks into the mortar: a running bond on whole voxels of the grid, as `VoxShed` lays them.
func _lay_bricks(m: VoxelModel, lo: Vector3, hi: Vector3, v: float, rng: RandomNumberGenerator, seed: int) -> void:
	var cells := m.cells()
	var ox := -float(cells.x) * v / 2.0
	m.set_material(VoxMaterials.index_of("brick"))
	var step := VoxShed.BRICK_LONG + VoxShed.JOINT
	var row := ceili(lo.y / v - 0.001)
	var top := floori(hi.y / v + 0.001)
	var course := 0
	while row + VoxShed.BRICK_TALL <= top:
		var shift := (step / 2) if course % 2 == 1 else 0
		for span: Vector2 in VoxShed._brick_spans(lo.x, hi.x, ox, v, step, shift):
			m.fill_box(Vector3(span.x, row * v, lo.z), Vector3(span.y, (row + VoxShed.BRICK_TALL) * v, hi.z), VoxShed.BRICK * rng.randf_range(0.82, 1.1), 0.05, seed + course)
		row += VoxShed.BRICK_TALL + VoxShed.JOINT
		course += 1

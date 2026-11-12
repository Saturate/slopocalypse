class_name VoxApartment
extends VoxGenerator
## A Danish apartment block: a long brick (or concrete panel) slab of 1 to 8 storeys, cut
## into stairwell sections. Each section is a stairwell bay with a flat on each side, so
## every flat reaches the street through its own stairwell. The street side is -Z.
##
## What makes it read as Danish: yellow or red brick walls in courses over a dark plinth,
## white-framed windows split by a mullion and a transom, a steep tiled gable roof with
## skylights and chimneys (or a flat roof with a parapet), a painted front door per stairwell
## with granite steps up to a raised ground floor over a basement, a column of stairwell
## windows half a storey out of step with the flats' windows, balconies on the courtyard side,
## and elevators added later as metal-clad towers on the back.
##
## Inside, each stairwell has switchback stairs (two flights a storey, a half landing at the
## turn) with a landing and a door into both flats on every floor, and each flat has rooms
## off a hall with plastered walls, wooden floors and furniture (see `ApartmentRooms`): how
## many rooms depends on the flat. `layout()` gives the plan in metres for tests and collision.

const WALLS: Array[String] = ["Yellow brick", "Red brick", "Concrete panels"]
const WALL_COLOURS := [Color(0.84, 0.71, 0.45), Color(0.6, 0.25, 0.17), Color(0.68, 0.67, 0.63)]
const ROOFS: Array[String] = ["Red tile gable", "Black tile gable", "Flat"]
const ROOF_COLOURS := [Color(0.62, 0.27, 0.18), Color(0.17, 0.17, 0.19), Color(0.2, 0.2, 0.21)]
const BALCONIES: Array[String] = ["None", "Cantilevered", "Recessed", "French"]
const BALCONY_SIDES: Array[String] = ["Courtyard", "Both sides"]
const RAILINGS: Array[String] = ["Steel bars", "Glass", "Panels"]
const INTERIORS: Array[String] = ["Empty", "Rooms", "Furnished"]
## Front doors: one colour per building, picked by the seed.
const DOOR_COLOURS := [Color(0.08, 0.34, 0.2), Color(0.52, 0.1, 0.07), Color(0.08, 0.24, 0.48), Color(0.1, 0.1, 0.11)]
## Balcony panels in the colours of 1960s and 70s housing estates.
const PANEL_COLOURS := [Color(0.85, 0.62, 0.2), Color(0.2, 0.45, 0.45), Color(0.7, 0.22, 0.15), Color(0.88, 0.87, 0.82)]
const TRIM := Color(0.93, 0.92, 0.88)
const GLASS := Color(0.17, 0.22, 0.27)
const RAIL_GLASS := Color(0.55, 0.66, 0.68)
const STEEL := Color(0.18, 0.19, 0.2)
const PLINTH := Color(0.24, 0.24, 0.24)
const GRANITE := Color(0.52, 0.52, 0.5)
const CONCRETE := Color(0.62, 0.61, 0.58)
const CLADDING := Color(0.27, 0.29, 0.31)
## Stairwell walls: a painted dado under plaster, and a stone floor.
const DADO := Color(0.36, 0.46, 0.36)
const DADO_HEIGHT := 1.1
const STAIR_FLOOR := Color(0.6, 0.58, 0.55)

## Floor to floor, and the floor slab's share of it.
const STOREY := 2.8
const SLAB := 0.25
## A raised ground floor over a basement sits this high; without a basement, one step up.
const BASEMENT_RISE := 0.9
const NO_BASEMENT_RISE := 0.15
const PLINTH_HEIGHT := 0.5
## Stairwell bay width (outside, wall to wall) and its stairs.
const STAIR_BAY := 3.0
const STEPS_PER_FLIGHT := 8
const TREAD := 0.28
const STEP_THICKNESS := 0.3
const LANDING := 1.3
const HALF_LANDING := 1.2
const DOOR := Vector2(1.1, 2.2)
const FLAT_DOOR := Vector2(0.9, 2.1)
const WINDOW := Vector2(1.2, 1.4)
const WINDOW_SILL := 0.9
const STAIR_WINDOW := Vector2(0.8, 1.3)
const STAIR_WINDOW_SILL := 2.65
const BASEMENT_WINDOW := Vector2(0.8, 0.35)
const BALCONY := Vector2(2.6, 1.4)
const RAIL_HEIGHT := 1.0
const ELEVATOR := Vector2(2.2, 2.0)
const ROOF_PITCH := 0.95
const EAVES_OVERHANG := 0.4
const VERGE_OVERHANG := 0.3
const PARAPET := 0.6
const CHIMNEY := 0.6
const STREET_STEP := 0.18
const STREET_TREAD := 0.3
## The voxel grid's cell limit (see the voxkit crate): a big block at fine voxels gets coarser
## voxels instead of being clipped.
const MAX_CELLS := 15 * 1024 * 1024


func title() -> String:
	return "Apartment block"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		param("floors", "Floors", 1.0, 8.0, 1.0, 4.0),
		param("stairwells", "Stairwells", 1.0, 4.0, 1.0, 2.0),
		param("elevators", "Elevators", 0.0, 4.0, 1.0, 1.0),
		choice("balconies", "Balconies", BALCONIES, 1),
		choice("balcony_sides", "Balconies on", BALCONY_SIDES, 0),
		choice("railing", "Railing", RAILINGS, 0),
		choice("walls", "Walls", WALLS, 0),
		choice("roof", "Roof", ROOFS, 0),
		param("roof_windows", "Skylights per flat", 0.0, 3.0, 1.0, 1.0),
		choice("basement", "Basement", ["No", "Yes"], 1),
		param("flat_width", "Flat width (m)", 4.5, 7.5, 0.25, 6.0),
		param("depth", "Depth (m)", 8.0, 13.0, 0.25, 10.0),
		param("windows", "Windows per flat", 1.0, 3.0, 1.0, 2.0),
		choice("interior", "Inside", INTERIORS, 2),
		voxel_param(0.1, 0.25, 0.15),
	]


## The plan in metres, model space (x and z centred, y up from the street):
## `length`, `depth`, `floors`, `levels` (walking height of each floor), `eaves`, `wall`
## (outer wall thickness), `bays` (stairwell bays as Vector2 x0, x1, outside), `flats`
## (Vector2 x0, x1, outside), `doors` (front door centres), `elevators` (tower boxes),
## `steps` (every stair step as a box, its top the tread) and `flat_plans` (per flat, its
## rooms, partitions and doors, the same on every storey; see `ApartmentRooms.plan_flat`).
func layout(values: Dictionary) -> Dictionary:
	var p := with_defaults(values)
	var v := _voxel(p)
	var floors := int(p["floors"])
	var sections := int(p["stairwells"])
	var fw: float = p["flat_width"]
	var d: float = p["depth"]
	var section := fw * 2.0 + STAIR_BAY
	var length := section * sections
	var ground := BASEMENT_RISE if int(p["basement"]) == 1 else NO_BASEMENT_RISE
	var wall := maxf(v * 2.0, 0.3)
	var levels: Array[float] = []
	for i in floors:
		levels.append(ground + i * STOREY)
	var bays: Array[Vector2] = []
	var flats: Array[Vector2] = []
	var doors: Array[Vector3] = []
	for s in sections:
		var x0 := -length / 2.0 + s * section
		flats.append(Vector2(x0, x0 + fw))
		bays.append(Vector2(x0 + fw, x0 + fw + STAIR_BAY))
		flats.append(Vector2(x0 + fw + STAIR_BAY, x0 + section))
		doors.append(Vector3(x0 + fw + STAIR_BAY / 2.0, ground + DOOR.y / 2.0, -d / 2.0))
	var elevators: Array[AABB] = []
	var count := mini(int(p["elevators"]), sections)
	var eaves := ground + floors * STOREY
	for j in count:
		# Spread over the stairwells: one elevator goes to the middle one.
		var s := int(round((j + 0.5) * sections / float(count) - 0.5))
		var cx := (bays[s].x + bays[s].y) / 2.0
		# Under a tiled roof the tower stops below the eaves; on a flat roof its machine room
		# stands above the parapet.
		var top := eaves + 1.4 if int(p["roof"]) == 2 else eaves - 0.5
		elevators.append(AABB(Vector3(cx - ELEVATOR.x / 2.0, 0.0, d / 2.0), Vector3(ELEVATOR.x, top, ELEVATOR.y)))
	var steps: Array[AABB] = []
	var rise := STOREY / 2.0 / STEPS_PER_FLIGHT
	var zf := -d / 2.0 + wall
	var run := STEPS_PER_FLIGHT * TREAD
	var zh := zf + LANDING + run
	for bay in bays:
		var inner := Vector2(bay.x + wall / 2.0, bay.y - wall / 2.0)
		var mid := (inner.x + inner.y) / 2.0
		for i in floors - 1:
			var level := levels[i]
			for k in range(1, STEPS_PER_FLIGHT + 1):
				# Up from the floor landing at the front towards the half landing...
				var top := level + k * rise
				var z0 := zf + LANDING + (k - 1) * TREAD
				steps.append(AABB(Vector3(inner.x, top - STEP_THICKNESS, z0), Vector3(mid - inner.x, STEP_THICKNESS, TREAD)))
			for k in range(1, STEPS_PER_FLIGHT + 1):
				# ...and back towards the front to the next floor's landing.
				var top := level + STOREY / 2.0 + k * rise
				var z0 := zh - k * TREAD
				steps.append(AABB(Vector3(mid, top - STEP_THICKNESS, z0), Vector3(inner.y - mid, STEP_THICKNESS, TREAD)))
	var plan := {
		"length": length, "depth": d, "floors": floors, "levels": levels, "eaves": eaves,
		"wall": wall, "bays": bays, "flats": flats, "doors": doors, "elevators": elevators,
		"steps": steps, "voxel": v, "ground": ground, "half_landing_z": zh,
	}
	var plans: Array[Dictionary] = []
	for f in flats.size():
		plans.append(_flat_plan(p, plan, f))
	plan["flat_plans"] = plans
	return plan


## A flat's floor inside its walls, as x and z.
static func inner_rect(plan: Dictionary, flat: Vector2) -> Rect2:
	var wall: float = plan["wall"]
	var half := float(plan["length"]) / 2.0
	var x0 := flat.x + (wall if is_equal_approx(flat.x, -half) else wall / 2.0)
	var x1 := flat.y - (wall if is_equal_approx(flat.y, half) else wall / 2.0)
	var z := float(plan["depth"]) / 2.0 - wall
	return Rect2(x0, -z, x1 - x0, z * 2.0)


func _flat_plan(p: Dictionary, plan: Dictionary, f: int) -> Dictionary:
	var flat: Vector2 = (plan["flats"] as Array)[f]
	var inner := inner_rect(plan, flat)
	var count := int(p["windows"])
	var wall: float = plan["wall"]
	var windows: Array[float] = []
	var tall: Array[Rect2] = []
	for k in count:
		var x := window_x(flat, count, k)
		windows.append(x)
		tall.append(Rect2(x - 0.8, inner.position.y, 1.6, 0.7))
		tall.append(Rect2(x - 0.8, inner.end.y - 0.7, 1.6, 0.7))
	# Balcony doors keep their floor clear; a loggia takes a bite out of the room behind it.
	var clear: Array[Rect2] = []
	var bx := window_x(flat, count, balcony_window(f, count))
	for side: float in [-1.0, 1.0]:
		if not _has_balconies(p, side):
			continue
		var reach := 1.0
		var half := 0.7
		if int(p["balconies"]) == 2:
			reach += BALCONY.y + wall
			half = maxf(1.0, minf(BALCONY.x, (flat.y - flat.x) / count - 0.4)) / 2.0 + 0.1
		var z0 := inner.end.y - reach if side > 0.0 else inner.position.y
		clear.append(Rect2(bx - half, z0, half * 2.0, reach))
	var seed := int(p["seed"]) * 7919 + f * 104729
	return ApartmentRooms.plan_flat(inner, f % 2 == 0, windows, seed, float(plan["voxel"]), clear, tall)


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var plan := layout(p)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["seed"])
	var seed := int(p["seed"])
	var v: float = plan["voxel"]
	var length: float = plan["length"]
	var d: float = plan["depth"]
	var eaves: float = plan["eaves"]
	var roof_kind := int(p["roof"])
	var rise := (d / 2.0 + EAVES_OVERHANG) * ROOF_PITCH if roof_kind != 2 else PARAPET
	var m := new_model()
	m.setup(_size(p, plan, rise), v)
	var wall_colour: Color = WALL_COLOURS[int(p["walls"])]
	_walls(m, p, plan, wall_colour, rng, seed)
	_interior(m, plan, v)
	var interior := int(p["interior"])
	_rooms(m, plan, interior >= 1)
	_stairs(m, plan, seed)
	var door_colour: Color = DOOR_COLOURS[rng.randi() % DOOR_COLOURS.size()]
	_windows(m, p, plan, v)
	_entrances(m, plan, door_colour, v, seed)
	_balconies(m, p, plan, rng, v, seed)
	if interior == 2:
		_furnish(m, plan, seed)
	_elevators(m, plan, v, seed)
	if roof_kind == 2:
		_flat_roof(m, plan, wall_colour, v, seed)
	else:
		_gable_roof(m, p, plan, wall_colour, ROOF_COLOURS[roof_kind], rise, v, seed)
	return m


## The voxel size asked for, or coarser if the block would not fit in the grid.
func _voxel(p: Dictionary) -> float:
	var v: float = p["voxel"]
	var sections := int(p["stairwells"])
	var length := (float(p["flat_width"]) * 2.0 + STAIR_BAY) * sections + 2.0
	var height := BASEMENT_RISE + int(p["floors"]) * STOREY + 9.0
	var depth := float(p["depth"]) + 2.0 * (ELEVATOR.y + 1.8)
	var cells := length * height * depth / (v * v * v)
	if cells > MAX_CELLS:
		v = pow(length * height * depth / MAX_CELLS, 1.0 / 3.0)
	return maxf(v, length / 1000.0)


func _size(p: Dictionary, plan: Dictionary, rise: float) -> Vector3:
	var v: float = plan["voxel"]
	var reach := EAVES_OVERHANG
	if int(p["balconies"]) == 1:
		reach = maxf(reach, BALCONY.y + 0.1)
	if (plan["elevators"] as Array).size() > 0:
		reach = maxf(reach, ELEVATOR.y + 1.7)
	var ground: float = plan["ground"]
	reach = maxf(reach, ceilf(ground / STREET_STEP) * STREET_TREAD + 0.1)
	var top: float = plan["eaves"] + rise + 1.5
	return Vector3(float(plan["length"]) + VERGE_OVERHANG * 2.0 + v * 4.0, top + v * 2.0, float(plan["depth"]) + reach * 2.0 + v * 4.0)


## The outer shell, solid: brick laid in courses (every voxel row its own shade) or concrete
## panels with dark joints, a dark plinth and a cornice band under the eaves.
func _walls(m: VoxelModel, p: Dictionary, plan: Dictionary, colour: Color, rng: RandomNumberGenerator, seed: int) -> void:
	var v: float = plan["voxel"]
	var x := float(plan["length"]) / 2.0
	var z := float(plan["depth"]) / 2.0
	var eaves: float = plan["eaves"]
	var panels := int(p["walls"]) == 2
	if panels:
		m.fill_box(Vector3(-x, 0.0, -z), Vector3(x, eaves, z), colour, 0.04, seed)
		var joint := colour.darkened(0.35)
		for level: float in plan["levels"]:
			m.paint_box(Vector3(-x - v, level - SLAB - v / 2.0, -z - v), Vector3(x + v, level - SLAB + v / 2.0, z + v), joint, 0.0, 0)
		var at := -x
		while at < x:
			m.paint_box(Vector3(at - v / 2.0, 0.0, -z - v), Vector3(at + v / 2.0, eaves, z + v), joint, 0.0, 0)
			at += float(p["flat_width"]) / 2.0
	else:
		var y := 0.0
		var row := 0
		while y < eaves - 0.001:
			var shade := rng.randf_range(0.93, 1.04) * (1.0 if row % 2 == 0 else 0.97)
			m.fill_box(Vector3(-x, y, -z), Vector3(x, minf(y + v, eaves), z), colour * shade, 0.1, seed + row)
			y += v
			row += 1
	var ground: float = plan["ground"]
	m.paint_box(Vector3(-x - v, 0.0, -z - v), Vector3(x + v, maxf(ground, PLINTH_HEIGHT), z + v), PLINTH, 0.05, seed)
	# Cornice: a band standing a voxel proud of the wall just under the eaves.
	m.fill_box(Vector3(-x - v, eaves - 0.35, -z - v), Vector3(x + v, eaves, z + v), colour.darkened(0.18), 0.05, seed)


## Each storey hollowed out: one room per flat, the stairwell bay open from floor to floor
## over the flights, with the next floor's slab left in everywhere else.
func _interior(m: VoxelModel, plan: Dictionary, v: float) -> void:
	var wall: float = plan["wall"]
	var inner := wall / 2.0
	var z := float(plan["depth"]) / 2.0 - wall
	var levels: Array = plan["levels"]
	var zf := -float(plan["depth"]) / 2.0 + wall
	var zh: float = plan["half_landing_z"]
	for i in levels.size():
		var level: float = levels[i]
		var ceiling := level + STOREY - SLAB
		for flat: Vector2 in plan["flats"]:
			var r := inner_rect(plan, flat)
			m.carve_box(Vector3(r.position.x, level, r.position.y), Vector3(r.end.x, ceiling, r.end.y))
		for bay: Vector2 in plan["bays"]:
			m.carve_box(Vector3(bay.x + inner, level, -z), Vector3(bay.y - inner, ceiling, z))
			m.paint_box(Vector3(bay.x + inner - v, level, -z - v), Vector3(bay.y - inner + v, ceiling + v, z + v), ApartmentRooms.PLASTER, 0.02, 0)
			m.paint_box(Vector3(bay.x + inner - v, level, -z - v), Vector3(bay.y - inner + v, level + DADO_HEIGHT, z + v), DADO, 0.04, 0)
			m.paint_box(Vector3(bay.x + inner, level - v, -z), Vector3(bay.y - inner, level, z), STAIR_FLOOR, 0.08, 0)
			if i < levels.size() - 1:
				# The stairs come up through the slab above.
				m.carve_box(Vector3(bay.x + inner, ceiling - v, zf + LANDING), Vector3(bay.y - inner, ceiling + SLAB, zh + HALF_LANDING))
			# A door from the landing into each flat.
			for side: float in [bay.x, bay.y]:
				m.carve_box(Vector3(side - inner - v, level, zf + 0.2), Vector3(side + inner + v, level + FLAT_DOOR.y, zf + 0.2 + FLAT_DOOR.x))


## Each flat's partitions, doorways and finishes on every storey; with `partitions` off, one
## plastered room with a wooden floor.
func _rooms(m: VoxelModel, plan: Dictionary, partitions: bool) -> void:
	var flats: Array = plan["flats"]
	var plans: Array = plan["flat_plans"]
	for level: float in plan["levels"]:
		for f in flats.size():
			ApartmentRooms.build_rooms(m, plans[f], inner_rect(plan, flats[f]), level, level + STOREY - SLAB, partitions)


## Furniture in every room, different on every storey.
func _furnish(m: VoxelModel, plan: Dictionary, seed: int) -> void:
	var levels: Array = plan["levels"]
	var plans: Array = plan["flat_plans"]
	for i in levels.size():
		for f in plans.size():
			var rng := RandomNumberGenerator.new()
			rng.seed = seed * 31 + f * 977 + i * 7
			var level: float = levels[i]
			ApartmentRooms.furnish(m, plans[f], level, level + STOREY - SLAB, rng)


func _stairs(m: VoxelModel, plan: Dictionary, seed: int) -> void:
	var wall: float = plan["wall"]
	var levels: Array = plan["levels"]
	var zh: float = plan["half_landing_z"]
	for step: AABB in plan["steps"]:
		m.fill_box(step.position, step.end, CONCRETE, 0.06, seed)
	for bay: Vector2 in plan["bays"]:
		for i in levels.size() - 1:
			var top := float(levels[i]) + STOREY / 2.0
			m.fill_box(Vector3(bay.x + wall / 2.0, top - SLAB, zh), Vector3(bay.y - wall / 2.0, top, zh + HALF_LANDING), CONCRETE, 0.06, seed)


## White frames with a mullion and a transom on every flat window, front and back; the
## stairwell's own windows half a storey up; small windows into the basement.
func _windows(m: VoxelModel, p: Dictionary, plan: Dictionary, v: float) -> void:
	var count := int(p["windows"])
	var z := float(plan["depth"]) / 2.0
	var wall: float = plan["wall"]
	var levels: Array = plan["levels"]
	var flats: Array = plan["flats"]
	for f in flats.size():
		var flat: Vector2 = flats[f]
		for k in count:
			var cx := window_x(flat, count, k)
			for side: float in [-1.0, 1.0]:
				# The balcony door takes this window's place.
				if k == balcony_window(f, count) and _has_balconies(p, side):
					continue
				for level: float in levels:
					_window(m, Vector3(cx, level + WINDOW_SILL, side * z), WINDOW, side, wall, v, true)
			if int(p["basement"]) == 1:
				_window(m, Vector3(cx, 0.25, -z), BASEMENT_WINDOW, -1.0, wall, v, false)
	for bay: Vector2 in plan["bays"]:
		var cx := (bay.x + bay.y) / 2.0
		for i in levels.size() - 1:
			# Lights the flight up to the half landing, so it sits half a storey out of step
			# with the flats' windows (and clears the door canopy on the ground floor).
			var y := float(levels[i]) + STAIR_WINDOW_SILL
			for side: float in [-1.0, 1.0]:
				_window(m, Vector3(cx, y, side * z), STAIR_WINDOW, side, wall, v, false)


## A window whose bottom middle is `at` on the wall facing `side` (-1 street, +1 courtyard).
func _window(m: VoxelModel, at: Vector3, size: Vector2, side: float, wall: float, v: float, mullion: bool) -> void:
	var half := size.x / 2.0
	var frame := maxf(v, 0.1)
	var outer := at.z
	var inner := at.z - side * wall
	m.fill_box(Vector3(at.x - half - frame, at.y - frame, minf(outer, outer + side * v)), Vector3(at.x + half + frame, at.y + size.y + frame, maxf(outer, outer + side * v)), TRIM, 0.03, 0)
	m.carve_box(Vector3(at.x - half, at.y, minf(inner, outer) - v * 2.0), Vector3(at.x + half, at.y + size.y, maxf(inner, outer) + v * 2.0))
	var glass := (outer + inner) / 2.0
	m.fill_box(Vector3(at.x - half, at.y, glass - v / 2.0), Vector3(at.x + half, at.y + size.y, glass + v / 2.0), GLASS, 0.0, 0)
	if mullion:
		m.fill_box(Vector3(at.x - v / 2.0, at.y, glass - v / 2.0), Vector3(at.x + v / 2.0, at.y + size.y, glass + v / 2.0), TRIM, 0.0, 0)
		var transom := at.y + size.y * 0.68
		m.fill_box(Vector3(at.x - half, transom - v / 2.0, glass - v / 2.0), Vector3(at.x + half, transom + v / 2.0, glass + v / 2.0), TRIM, 0.0, 0)
	# Sill: a ledge under the frame.
	var sill_out := outer + side * v * 2.0
	m.fill_box(Vector3(at.x - half - frame, at.y - frame - v, minf(outer, sill_out)), Vector3(at.x + half + frame, at.y - frame, maxf(outer, sill_out)), TRIM.darkened(0.1), 0.03, 0)


## A painted door per stairwell under a concrete canopy, with granite steps up from the street
## when the ground floor is raised.
func _entrances(m: VoxelModel, plan: Dictionary, colour: Color, v: float, seed: int) -> void:
	var wall: float = plan["wall"]
	var ground: float = plan["ground"]
	var z := -float(plan["depth"]) / 2.0
	for door: Vector3 in plan["doors"]:
		var half := DOOR.x / 2.0
		m.fill_box(Vector3(door.x - half - 0.15, ground - 0.05, z - v), Vector3(door.x + half + 0.15, ground + DOOR.y + 0.15, z), TRIM, 0.03, 0)
		m.carve_box(Vector3(door.x - half, ground, z - v * 2.0), Vector3(door.x + half, ground + DOOR.y, z + wall + v))
		# The leaf is set back into the opening, with a glass panel in its top half.
		var leaf := z + wall * 0.5
		m.fill_box(Vector3(door.x - half, ground, leaf - v / 2.0), Vector3(door.x + half, ground + DOOR.y, leaf + v / 2.0), colour, 0.04, seed)
		m.fill_box(Vector3(door.x - half + 0.2, ground + DOOR.y * 0.5, leaf - v / 2.0), Vector3(door.x + half - 0.2, ground + DOOR.y - 0.2, leaf + v / 2.0), GLASS, 0.0, 0)
		m.fill_box(Vector3(door.x - 0.9, ground + DOOR.y + 0.15, z - 0.9), Vector3(door.x + 0.9, ground + DOOR.y + 0.3, z), CONCRETE, 0.04, seed)
		var steps := int(ceilf(ground / STREET_STEP))
		for k in range(1, steps + 1):
			var top := minf(k * STREET_STEP, ground)
			var out := (steps - k + 1) * STREET_TREAD
			m.fill_box(Vector3(door.x - 0.8, 0.0, z - out), Vector3(door.x + 0.8, top, z), GRANITE, 0.05, seed + k)


func _balconies(m: VoxelModel, p: Dictionary, plan: Dictionary, rng: RandomNumberGenerator, v: float, seed: int) -> void:
	var style := int(p["balconies"])
	if style == 0:
		return
	var railing := int(p["railing"])
	# Panels change colour from one stairwell to the next.
	var first := rng.randi() % PANEL_COLOURS.size()
	var wall: float = plan["wall"]
	var z := float(plan["depth"]) / 2.0
	var levels: Array = plan["levels"]
	var flats: Array = plan["flats"]
	var count := int(p["windows"])
	for f in flats.size():
		var flat: Vector2 = flats[f]
		var panel: Color = PANEL_COLOURS[(first + f / 2) % PANEL_COLOURS.size()]
		var cx := window_x(flat, count, balcony_window(f, count))
		var half := maxf(1.0, minf(BALCONY.x, (flat.y - flat.x) / count - 0.4)) / 2.0
		for side: float in [-1.0, 1.0]:
			if not _has_balconies(p, side):
				continue
			var face := side * z
			for level: float in levels:
				match style:
					1:
						var out := face + side * BALCONY.y
						m.fill_box(Vector3(cx - half, level - 0.2, minf(face, out)), Vector3(cx + half, level, maxf(face, out)), CONCRETE, 0.05, seed)
						_door(m, Vector3(cx, level, face), side, wall, v)
						_railing(m, Vector3(cx - half, level, minf(face, out)), Vector3(cx + half, level + RAIL_HEIGHT, maxf(face, out)), side, railing, panel, v)
					2:
						# A loggia: the facade stepped in, with a new wall and door at the back.
						var back := face - side * BALCONY.y
						m.carve_box(Vector3(cx - half, level, minf(face, back) - v * 0.5), Vector3(cx + half, level + STOREY - SLAB, maxf(face, back) + v * 0.5))
						var inner := back - side * wall
						m.fill_box(Vector3(cx - half, level, minf(back, inner)), Vector3(cx + half, level + STOREY - SLAB, maxf(back, inner)), WALL_COLOURS[int(p["walls"])], 0.08, seed)
						_door(m, Vector3(cx, level, back), side, wall, v)
						var rail := face - side * v
						_railing(m, Vector3(cx - half, level, minf(face, rail)), Vector3(cx + half, level + RAIL_HEIGHT, maxf(face, rail)), side, railing, panel, v)
					3:
						_door(m, Vector3(cx, level, face), side, wall, v)
						var rail := face + side * v * 2.0
						_railing(m, Vector3(cx - 0.6, level, minf(face, rail)), Vector3(cx + 0.6, level + RAIL_HEIGHT, maxf(face, rail)), side, railing, panel, v, true)


## Where window `k` of `count` sits along a flat.
static func window_x(flat: Vector2, count: int, k: int) -> float:
	return lerpf(flat.x, flat.y, (k + 0.5) / count)


## Which window a flat's balcony replaces: the one next to the stairwell, so the two flats of
## a section have their balconies side by side.
static func balcony_window(flat_index: int, count: int) -> int:
	return count - 1 if flat_index % 2 == 0 else 0


func _has_balconies(p: Dictionary, side: float) -> bool:
	return int(p["balconies"]) != 0 and (side > 0.0 or int(p["balcony_sides"]) == 1)


## A glazed balcony door through the wall whose outer face is at `at.z`, sill at `at.y`.
func _door(m: VoxelModel, at: Vector3, side: float, wall: float, v: float) -> void:
	var half := 0.5
	var outer := at.z
	var inner := at.z - side * wall
	m.fill_box(Vector3(at.x - half - v, at.y, minf(outer, outer + side * v)), Vector3(at.x + half + v, at.y + FLAT_DOOR.y + v, maxf(outer, outer + side * v)), TRIM, 0.03, 0)
	m.carve_box(Vector3(at.x - half, at.y, minf(outer, inner) - v * 2.0), Vector3(at.x + half, at.y + FLAT_DOOR.y, maxf(outer, inner) + v * 2.0))
	var glass := (outer + inner) / 2.0
	m.fill_box(Vector3(at.x - half, at.y, glass - v / 2.0), Vector3(at.x + half, at.y + FLAT_DOOR.y, glass + v / 2.0), GLASS, 0.0, 0)
	m.fill_box(Vector3(at.x - half, at.y + 0.9, glass - v / 2.0), Vector3(at.x + half, at.y + 0.9 + v, glass + v / 2.0), TRIM, 0.0, 0)


## A railing along the open sides of the box `lo..hi`; `side` says which way is out.
## `front_only` leaves out the sides (a railing straight across a door).
func _railing(m: VoxelModel, lo: Vector3, hi: Vector3, side: float, kind: int, panel: Color, v: float, front_only := false) -> void:
	var front := hi.z if side > 0.0 else lo.z
	var faces: Array[AABB] = [AABB(Vector3(lo.x, lo.y, minf(front, front - side * v)), Vector3(hi.x - lo.x, hi.y - lo.y, v))]
	if not front_only:
		faces.append(AABB(Vector3(lo.x, lo.y, lo.z), Vector3(v, hi.y - lo.y, hi.z - lo.z)))
		faces.append(AABB(Vector3(hi.x - v, lo.y, lo.z), Vector3(v, hi.y - lo.y, hi.z - lo.z)))
	for f in faces:
		var top := f.end.y
		match kind:
			0:
				m.fill_box(Vector3(f.position.x, top - v, f.position.z), f.end, STEEL, 0.0, 0)
				m.fill_box(f.position, Vector3(f.end.x, f.position.y + v, f.end.z), STEEL, 0.0, 0)
				# Bars every other voxel.
				var along_x := f.size.x > f.size.z
				var from := f.position.x if along_x else f.position.z
				var to := f.end.x if along_x else f.end.z
				var at := from
				while at < to:
					if along_x:
						m.fill_box(Vector3(at, f.position.y, f.position.z), Vector3(at + v * 0.5, top, f.end.z), STEEL, 0.0, 0)
					else:
						m.fill_box(Vector3(f.position.x, f.position.y, at), Vector3(f.end.x, top, at + v * 0.5), STEEL, 0.0, 0)
					at += v * 2.0
			1:
				m.fill_box(f.position, Vector3(f.end.x, top - v, f.end.z), RAIL_GLASS, 0.0, 0)
				m.fill_box(Vector3(f.position.x, top - v, f.position.z), f.end, STEEL, 0.0, 0)
			_:
				m.fill_box(f.position, f.end, panel, 0.04, 0)


## Elevator towers added on the courtyard side: metal cladding, a glass strip up the middle
## and a door at the bottom.
func _elevators(m: VoxelModel, plan: Dictionary, v: float, seed: int) -> void:
	var ground: float = plan["ground"]
	for box: AABB in plan["elevators"]:
		var top := box.end.y
		m.fill_box(box.position, Vector3(box.end.x, top, box.end.z), CLADDING, 0.05, seed)
		var cx := box.get_center().x
		m.fill_box(Vector3(cx - 0.4, ground + 0.4, box.end.z - v), Vector3(cx + 0.4, top - 0.4, box.end.z + v * 0.5), RAIL_GLASS, 0.0, 0)
		m.carve_box(Vector3(cx - 0.5, ground, box.end.z - v * 2.0), Vector3(cx + 0.5, ground + 2.1, box.end.z + v))
		m.fill_box(Vector3(cx - 0.5, ground, box.end.z - v * 2.0), Vector3(cx + 0.5, ground + 2.1, box.end.z - v), STEEL, 0.0, 0)
		m.fill_box(Vector3(box.position.x - v, top, box.position.z - v), Vector3(box.end.x + v, top + v, box.end.z + v), STEEL, 0.0, 0)
		# Steps down to the courtyard from the raised ground floor.
		var steps := int(ceilf(ground / STREET_STEP))
		for k in range(1, steps + 1):
			var out := (steps - k + 1) * STREET_TREAD
			m.fill_box(Vector3(cx - 0.8, 0.0, box.end.z), Vector3(cx + 0.8, minf(k * STREET_STEP, ground), box.end.z + out), GRANITE, 0.05, seed + k)


## A steep tiled saddle roof: gable ends in the wall material, tiles in rows with a darker
## ridge, skylights over the top-floor flats and a chimney per stairwell.
func _gable_roof(m: VoxelModel, p: Dictionary, plan: Dictionary, wall: Color, tile: Color, rise: float, v: float, seed: int) -> void:
	var x := float(plan["length"]) / 2.0
	var d := float(plan["depth"]) / 2.0
	var eaves: float = plan["eaves"]
	var slope := rise / (d + EAVES_OVERHANG)
	# Gables: the attic filled in the wall colour under the slopes.
	# Gables: the attic filled in the wall colour, each layer kept under the tiles so the
	# wall never shows through the roof.
	var y := eaves
	while y < eaves + slope * d:
		var half := d - (y + v - eaves) / slope
		if half > 0.0:
			m.fill_box(Vector3(-x, y, -half), Vector3(x, y + v, half), wall, 0.08, seed)
		y += v
	var thick := maxf(v * 2.0, 0.25)
	# Skylights evenly along the roof, so they fall between the chimneys.
	var skylights: Array[Vector2] = []
	var count := int(p["roof_windows"]) * (plan["flats"] as Array).size()
	for k in count:
		var cx := lerpf(-x, x, (k + 0.5) / count)
		skylights.append(Vector2(cx - 0.4, cx + 0.4))
	var z := -d - EAVES_OVERHANG
	var row := 0
	while z < d + EAVES_OVERHANG:
		var mid := z + v / 2.0
		var top := eaves + slope * (d - absf(mid))
		var shade := tile * (1.0 if row % 3 != 0 else 0.93)
		if absf(mid) < v * 1.5:
			shade = tile.darkened(0.3)
		m.fill_box(Vector3(-x - VERGE_OVERHANG, top - thick, z), Vector3(x + VERGE_OVERHANG, top, z + v), shade, 0.08, seed + row)
		# Skylights sit a third of the way up each slope.
		var up := (d - absf(mid)) / d
		if up > 0.25 and up < 0.45:
			# Flush with the tiles: a metal frame round the glass.
			for s in skylights:
				m.fill_box(Vector3(s.x - v, top - v, z), Vector3(s.y + v, top, z + v), STEEL, 0.0, 0)
				m.fill_box(Vector3(s.x, top - v, z), Vector3(s.y, top, z + v), GLASS, 0.0, 0)
		z += v
		row += 1
	var ridge := eaves + slope * d
	for bay: Vector2 in plan["bays"]:
		var cx := (bay.x + bay.y) / 2.0
		var c := wall.darkened(0.1) if int(p["walls"]) != 2 else WALL_COLOURS[1]
		m.fill_box(Vector3(cx - CHIMNEY / 2.0, ridge - 1.5, 0.8), Vector3(cx + CHIMNEY / 2.0, ridge + 1.1, 0.8 + CHIMNEY), c, 0.1, seed)
		m.fill_box(Vector3(cx - CHIMNEY / 2.0 - v, ridge + 1.1, 0.8 - v), Vector3(cx + CHIMNEY / 2.0 + v, ridge + 1.1 + v, 0.8 + CHIMNEY + v), CONCRETE, 0.0, 0)


## A flat roof in roofing felt behind a parapet with a metal cap, with vents on top.
func _flat_roof(m: VoxelModel, plan: Dictionary, wall: Color, v: float, seed: int) -> void:
	var x := float(plan["length"]) / 2.0
	var z := float(plan["depth"]) / 2.0
	var eaves: float = plan["eaves"]
	var t: float = plan["wall"]
	m.fill_box(Vector3(-x, eaves, -z), Vector3(x, eaves + PARAPET, z), wall, 0.08, seed)
	m.carve_box(Vector3(-x + t, eaves, -z + t), Vector3(x - t, eaves + PARAPET + v, z - t))
	m.fill_box(Vector3(-x + t, eaves - v, -z + t), Vector3(x - t, eaves, z - t), ROOF_COLOURS[2], 0.05, seed)
	m.fill_box(Vector3(-x - v, eaves + PARAPET, -z - v), Vector3(x + v, eaves + PARAPET + v, z + v), STEEL.lightened(0.3), 0.0, 0)
	m.carve_box(Vector3(-x + t, eaves + PARAPET, -z + t), Vector3(x - t, eaves + PARAPET + v * 2.0, z - t))
	for bay: Vector2 in plan["bays"]:
		var cx := (bay.x + bay.y) / 2.0
		m.fill_box(Vector3(cx - 0.3, eaves, -0.3), Vector3(cx + 0.3, eaves + 0.9, 0.3), STEEL.lightened(0.2), 0.04, seed)

class_name VoxHarbourProp
extends VoxGenerator
## Small things that stand about a harbour, one kind at a time:
## - fish crates: a stack of ribbed plastic crates with hand holes, the top one full of ice;
## - net pile: a heap of fishing net with a line of floats through it and a rope coiled on top;
## - buoy: a mooring buoy, a round float with a lifting ring on top and a chain below;
## - fuel tank: a horizontal tank on two steel cradles with a hose and pump at one end.
## `colour` picks the crates', floats' and buoy's paint. Each stands on y 0, centred;
## `collision` gives the boxes for the kind.

const KINDS: Array[String] = ["Fish crates", "Net pile", "Buoy", "Fuel tank"]
const FISH_CRATES := 0
const NET_PILE := 1
const BUOY := 2
const FUEL_TANK := 3
const COLOURS: Array[String] = ["Blue", "Red", "Orange", "Green", "White"]
const PAINT := [Color(0.16, 0.36, 0.62), Color(0.7, 0.16, 0.12), Color(0.9, 0.45, 0.1), Color(0.22, 0.45, 0.28), Color(0.88, 0.88, 0.85)]
const ICE := Color(0.82, 0.88, 0.9)
const NET := Color(0.2, 0.42, 0.22)
const ROPE := Color(0.72, 0.62, 0.42)
const CHAIN := Color(0.3, 0.24, 0.2)
const TANK := Color(0.35, 0.42, 0.3)
const STEEL := Color(0.4, 0.42, 0.43)
const HOSE := Color(0.1, 0.1, 0.11)
const PUMP := Color(0.7, 0.16, 0.12)
const LABEL := Color(0.85, 0.7, 0.2)
const BAND_LIGHT := Color(0.9, 0.9, 0.86)
## One fish crate, metres.
const CRATE := Vector3(0.8, 0.3, 0.5)
const BUOY_RADIUS := 0.5
const TANK_LENGTH := 2.4
const TANK_RADIUS := 0.6
## The tank's underside clears the ground by this much on its cradles.
const TANK_CLEAR := 0.25
const NET_SIZE := Vector3(2.0, 0.7, 1.4)
## The pump and its hose reach this far past the tank's +x end.
const PUMP_REACH := 0.5
## The tank's ends are this long and a little narrower, metres.
const END := 0.12


func title() -> String:
	return "Harbour prop"


func params() -> Array[Dictionary]:
	return [
		seed_param(),
		choice("kind", "Kind", KINDS, FISH_CRATES),
		choice("colour", "Colour", COLOURS, 0),
		param("count", "Crates (fish crates)", 1.0, 6.0, 1.0, 3.0),
		voxel_param(0.02, 0.08, 0.04),
	]


## Collision boxes (model space) for the kind.
static func collision(values: Dictionary) -> Array[AABB]:
	var p := VoxHarbourProp.new().with_defaults(values)
	match int(p["kind"]):
		NET_PILE:
			return [AABB(Vector3(-NET_SIZE.x / 2.0, 0.0, -NET_SIZE.z / 2.0), Vector3(NET_SIZE.x, NET_SIZE.y, NET_SIZE.z))]
		BUOY:
			return [AABB(Vector3(-BUOY_RADIUS, 0.0, -BUOY_RADIUS), Vector3(BUOY_RADIUS * 2.0, BUOY_RADIUS * 2.0, BUOY_RADIUS * 2.0))]
		FUEL_TANK:
			var top := TANK_CLEAR + TANK_RADIUS * 2.0
			return [AABB(Vector3(-TANK_LENGTH / 2.0, 0.0, -TANK_RADIUS), Vector3(TANK_LENGTH + PUMP_REACH, top, TANK_RADIUS * 2.0))]
	var h := CRATE.y * float(int(p["count"]))
	return [AABB(Vector3(-CRATE.x / 2.0, 0.0, -CRATE.z / 2.0), Vector3(CRATE.x, h, CRATE.z))]


func build(values: Dictionary) -> VoxelModel:
	var p := with_defaults(values)
	var seed := int(p["seed"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var v: float = p["voxel"]
	var paint: Color = PAINT[clampi(int(p["colour"]), 0, PAINT.size() - 1)]
	var m := new_model()
	match int(p["kind"]):
		NET_PILE:
			_net_pile(m, paint, v, rng, seed)
		BUOY:
			_buoy(m, paint, v, seed)
		FUEL_TANK:
			_fuel_tank(m, v, seed)
		_:
			_fish_crates(m, paint, int(p["count"]), v, rng, seed)
	return m


## Crates stacked straight, each a little off square, ribbed sides, hand holes in the ends,
## the top one open with ice in it.
func _fish_crates(m: VoxelModel, paint: Color, count: int, v: float, rng: RandomNumberGenerator, seed: int) -> void:
	m.setup(Vector3(CRATE.x + 0.2 + v * 4.0, CRATE.y * count + v * 4.0, CRATE.z + 0.2 + v * 4.0), v)
	m.set_material(VoxMaterials.index_of("furniture"))
	var hx := CRATE.x / 2.0
	var hz := CRATE.z / 2.0
	for i in count:
		var y0 := CRATE.y * i
		var y1 := y0 + CRATE.y - v * 0.5
		var off := Vector3(rng.randf_range(-0.04, 0.04), 0.0, rng.randf_range(-0.03, 0.03))
		var shade := paint * rng.randf_range(0.9, 1.06)
		m.fill_box(Vector3(-hx, y0, -hz) + off, Vector3(hx, y1, hz) + off, shade, 0.04, seed + i)
		# A lip round the top and ribs down the sides.
		m.fill_box(Vector3(-hx - v, y1 - v * 1.5, -hz - v) + off, Vector3(hx + v, y1, hz + v) + off, shade.darkened(0.1), 0.03, seed + i)
		var rib := -hx + 0.12
		while rib < hx - 0.06:
			for sz: float in [-1.0, 1.0]:
				m.fill_box(Vector3(rib, y0 + v, sz * hz - v) + off, Vector3(rib + v, y1, sz * hz + v) + off, shade.darkened(0.08), 0.03, seed + i)
			rib += 0.16
		for sx: float in [-1.0, 1.0]:
			m.carve_box(Vector3(sx * hx - v * 2.0, y1 - 0.11, -0.09) + off, Vector3(sx * hx + v * 2.0, y1 - 0.05, 0.09) + off)
		if i == count - 1:
			var wall := maxf(v * 1.5, 0.04)
			m.carve_box(Vector3(-hx + wall, y0 + wall, -hz + wall) + off, Vector3(hx - wall, y1 + v, hz - wall) + off)
			m.fill_box(Vector3(-hx + wall, y0 + wall, -hz + wall) + off, Vector3(hx - wall, y1 - 0.06, hz - wall) + off, ICE, 0.08, seed + 50)


## A low heap of netting, lumpy, with orange or painted floats on a line through it and a
## rope coiled on top.
func _net_pile(m: VoxelModel, paint: Color, v: float, rng: RandomNumberGenerator, seed: int) -> void:
	# The blob's bumps reach a quarter past its radii.
	m.setup(Vector3(NET_SIZE.x * 1.3 + v * 6.0, NET_SIZE.y * 1.3 + 0.3 + v * 4.0, NET_SIZE.z * 1.3 + v * 6.0), v)
	m.set_material(VoxMaterials.index_of("furniture"))
	m.fill_blob(Vector3(0.0, 0.0, 0.0), Vector3(NET_SIZE.x / 2.0, NET_SIZE.y, NET_SIZE.z / 2.0), 0.25, 3.0, NET, 0.15, seed)
	m.fill_blob(Vector3(0.3, 0.1, 0.1), Vector3(0.6, NET_SIZE.y * 0.9, 0.5), 0.3, 4.0, NET.lightened(0.08), 0.15, seed + 1)
	# Floats on the head line, round over the top of the heap.
	# Sat on the heap's surface (found by stepping down from above), so they are not buried.
	var count := 9
	for i in count:
		var t := float(i) / (count - 1)
		var x := lerpf(-NET_SIZE.x * 0.45, NET_SIZE.x * 0.45, t)
		var z := sin(t * PI * 1.5) * NET_SIZE.z * 0.3
		var y := NET_SIZE.y + 0.2
		while y > 0.0 and m.colour_at(Vector3(x, y, z)).a == 0.0:
			y -= v
		m.fill_ellipsoid(Vector3(x, y + 0.05, z), Vector3(0.12, 0.09, 0.09) + Vector3.ONE * rng.randf_range(0.0, 0.02), paint, 0.05, seed + 10 + i)
	# Mesh: a darker grid over the heap so it reads as netting.
	var step := maxf(v * 3.0, 0.12)
	var gx := -NET_SIZE.x
	while gx < NET_SIZE.x:
		m.paint_box(Vector3(gx, 0.0, -NET_SIZE.x), Vector3(gx + v * 0.99, NET_SIZE.y * 2.0, NET_SIZE.x), NET.darkened(0.5), 0.05, seed + 2)
		gx += step
	var gz := -NET_SIZE.x
	while gz < NET_SIZE.x:
		m.paint_box(Vector3(-NET_SIZE.x, 0.0, gz), Vector3(NET_SIZE.x, NET_SIZE.y * 2.0, gz + v * 0.99), NET.darkened(0.5), 0.05, seed + 2)
		gz += step
	# A coil of rope, two turns.
	var top := NET_SIZE.y * 0.75
	for k in 2:
		var r := 0.22 - k * 0.07
		var segments := 12
		for i in segments:
			var a0 := TAU * i / segments
			var a1 := TAU * (i + 1) / segments
			var c := Vector3(-0.45, top + k * 0.05, 0.15)
			m.fill_capsule(c + Vector3(cos(a0), 0.0, sin(a0)) * r, c + Vector3(cos(a1), 0.0, sin(a1)) * r, 0.035, 0.035, ROPE, 0.06, seed + 30)


## A round float with a band round its middle, a lifting ring on top and a length of chain
## from the bottom.
func _buoy(m: VoxelModel, paint: Color, v: float, seed: int) -> void:
	var r := BUOY_RADIUS
	m.setup(Vector3((r + 0.4) * 2.0 + v * 6.0, r * 2.0 + 0.4 + v * 4.0, r * 2.0 + v * 6.0), v)
	m.set_material(VoxMaterials.index_of("sheet_metal"))
	m.fill_ellipsoid(Vector3(0.0, r, 0.0), Vector3(r, r * 0.95, r), paint, 0.05, seed)
	m.paint_box(Vector3(-r * 2.0, r * 0.85, -r * 2.0), Vector3(r * 2.0, r * 1.15, r * 2.0), BAND_LIGHT if paint.get_luminance() < 0.6 else PUMP, 0.03, seed)
	m.fill_cylinder(Vector3(0.0, r * 1.85, 0.0), 0.12, 0.08, STEEL, 0.03, seed)
	# The lifting ring, edge on.
	var ring := 0.13
	var segments := 10
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var c := Vector3(0.0, r * 1.95 + ring, 0.0)
		m.fill_capsule(c + Vector3(cos(a0) * ring, sin(a0) * ring, 0.0), c + Vector3(cos(a1) * ring, sin(a1) * ring, 0.0), 0.03, 0.03, STEEL, 0.03, seed)
	# Chain from the bottom, lying off to one side, links in alternating shades.
	var link := maxf(0.05, v)
	m.fill_box(Vector3(0.0, 0.0, -link / 2.0), Vector3(r + 0.3, link, link / 2.0), CHAIN, 0.1, seed)
	for i in 8:
		var x := 0.1 + i * 0.12
		m.paint_box(Vector3(x, 0.0, -link), Vector3(x + 0.06, link, link), CHAIN.darkened(0.3), 0.1, seed + i)


## A horizontal tank on two cradles, a filler cap on top, a pump box and a coiled hose at one
## end.
func _fuel_tank(m: VoxelModel, v: float, seed: int) -> void:
	var r := TANK_RADIUS
	var half := TANK_LENGTH / 2.0
	m.setup(Vector3(TANK_LENGTH + PUMP_REACH * 2.0 + v * 4.0, TANK_CLEAR + r * 2.0 + 0.3 + v * 4.0, r * 2.0 + v * 6.0), v)
	m.set_material(VoxMaterials.index_of("sheet_metal"))
	var cy := TANK_CLEAR + r
	# The tank row by row as long boxes (a round section along x), the ends a little smaller
	# so it reads rounded; two raised bands.
	_tank_body(m, -half + END, half - END, cy, r, v, TANK, seed)
	for side: float in [-1.0, 1.0]:
		var a := side * (half - END)
		var b := side * half
		_tank_body(m, minf(a, b), maxf(a, b), cy, r - END * 0.8, v, TANK.darkened(0.05), seed)
	for at: float in [-half * 0.75, half * 0.75]:
		_tank_body(m, at - v, at + v, cy, r + v, v, TANK.darkened(0.15), seed + 1)
	for at: float in [-half * 0.6, half * 0.6]:
		m.fill_box(Vector3(at - 0.08, 0.0, -r * 0.85), Vector3(at + 0.08, cy, r * 0.85), STEEL, 0.05, seed + 2)
		m.fill_box(Vector3(at - 0.1, 0.0, -r * 0.95), Vector3(at + 0.1, 0.06, r * 0.95), STEEL.darkened(0.2), 0.05, seed + 2)
	m.fill_cylinder(Vector3(-half * 0.3, cy + r - v, 0.0), 0.1, 0.12 + v, STEEL, 0.03, seed + 3)
	# Pump on the end, a hose hanging down and coiled on its hook.
	m.fill_box(Vector3(half, 0.0, -0.2), Vector3(half + 0.25, 1.1, 0.2), PUMP, 0.04, seed + 4)
	m.fill_box(Vector3(half - 0.02, 1.1, -0.22), Vector3(half + 0.27, 1.18, 0.22), STEEL, 0.03, seed + 4)
	m.fill_box(Vector3(half + 0.25, 0.6, -0.08), Vector3(half + 0.3, 0.72, 0.08), STEEL, 0.03, seed + 4)
	m.fill_capsule(Vector3(half + 0.1, 0.9, 0.0), Vector3(half + 0.12, cy + r * 0.3, 0.0), 0.035, 0.035, HOSE, 0.04, seed + 5)
	for i in 10:
		var a0 := TAU * i / 10.0
		var a1 := TAU * (i + 1) / 10.0
		var c := Vector3(half + 0.32, 0.4, 0.0)
		m.fill_capsule(c + Vector3(0.0, sin(a0) * 0.18, cos(a0) * 0.18), c + Vector3(0.0, sin(a1) * 0.18, cos(a1) * 0.18), 0.035, 0.035, HOSE, 0.04, seed + 5)
	m.paint_box(Vector3(-half * 0.2, cy - r * 0.35, -r - v), Vector3(half * 0.4, cy + r * 0.05, r + v), LABEL, 0.03, seed + 6)


## A horizontal cylinder along x from `x0` to `x1`, axis at height `cy`, one long box per row.
func _tank_body(m: VoxelModel, x0: float, x1: float, cy: float, r: float, v: float, colour: Color, seed: int) -> void:
	var y := cy - r
	while y < cy + r:
		var dy := y + v * 0.5 - cy
		var half_z := sqrt(maxf(0.0, r * r - dy * dy))
		m.fill_box(Vector3(x0, y, -half_z), Vector3(x1, y + v, half_z), colour, 0.04, seed)
		y += v

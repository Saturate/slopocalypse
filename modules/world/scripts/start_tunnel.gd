class_name StartTunnel
extends Node3D
## Where the world begins: the tunnel the road comes out of. The ground is a trench through
## the start mountain here (TerrainHeights); this adds the tunnel itself (lining, roof,
## headwall, the cave-in that seals it), rock over the roof up to the mountain's surface so
## the slope looks whole from outside, and the collision for all of it. Lamps light it on
## clients.

## Voxel size of the rock over the roof.
const COVER_VOXEL := 0.5
## Headwall stands this far above the ground it holds back.
const HEADWALL_MARGIN := 0.4
## A step in the ground at the portal smaller than this needs no headwall.
const HEADWALL_MIN_STEP := 0.3
const HEADWALL_STEP := 0.5
## The rock over the roof reaches this far past the trench on each side: the ground's height
## samples are a metre or more apart, so the slope rises from the trench floor over that
## distance and would show as a dark groove beside a cover only as wide as the trench.
const COVER_OVERHANG := 2.0
## Cover tops stand this much over the ground they continue, so the two don't flicker.
const COVER_LIFT := 0.1
const LAMP_ENERGY := 1.6
const LAMP_RANGE := 10.0
const LAMP_COLOUR := Color(1.0, 0.9, 0.74)

@export_file("*.json") var config_path: String = "res://modules/world/data/world.json"

var _visual := DisplayServer.get_name() != "headless"


func _ready() -> void:
	var config: Variant = Data.load_json(config_path)
	if not config is Dictionary:
		return
	var heights := TerrainHeights.new(config)
	if not heights.has_tunnel() or heights.road == null:
		return
	var p := tunnel_params(heights)
	var portal: float = heights.start["portal_z"]
	var end: float = heights.start["tunnel_end_z"]
	var mid := (portal + end) / 2.0
	var floor_y := heights.road.height_at(mid)
	position = Vector3(heights.road.x_at(mid), floor_y - VoxTunnel.FLOOR, mid)
	var top := headwall_top(heights, floor_y)
	p["headwall_width"] = headwall_width(heights)
	var body := StaticBody3D.new()
	body.name = "Collision"
	add_child(body)
	for box in VoxTunnel.collision_boxes(p, top):
		_add_box(body, box)
	var cover := _cover_profile(heights, p, floor_y)
	for box in cover["boxes"]:
		_add_box(body, box)
	if not _visual:
		return
	var tunnel := MeshInstance3D.new()
	tunnel.name = "Tunnel"
	tunnel.mesh = VoxGenerator.to_mesh(VoxTunnel.new().build_with_top(p, top))
	add_child(tunnel)
	var rock := MeshInstance3D.new()
	rock.name = "Cover"
	rock.mesh = VoxGenerator.to_mesh(_cover_model(p, cover))
	# The ground's own shader, so the rock over the roof is lit and varied exactly like the
	# slope around it instead of showing as a lighter strip.
	var ground_material := ShaderMaterial.new()
	ground_material.shader = load(VoxelWorld.SHADER)
	rock.material_override = ground_material
	rock.set_instance_shader_parameter(&"voxel", COVER_VOXEL)
	add_child(rock)
	for at in VoxTunnel.lamp_positions(p):
		var lamp := OmniLight3D.new()
		lamp.light_color = LAMP_COLOUR
		lamp.light_energy = LAMP_ENERGY
		lamp.omni_range = LAMP_RANGE
		lamp.shadow_enabled = false
		lamp.position = at + Vector3(-signf(at.x) * 0.5, VoxTunnel.FLOOR - 0.2, 0.0)
		add_child(lamp)


## The tunnel generator's values for this world's start block.
static func tunnel_params(heights: TerrainHeights) -> Dictionary:
	var s := heights.start
	var width := float(s["tunnel_half_width"]) * 2.0
	var height: float = s["tunnel_height"]
	var rise := minf(width * 0.15, height * 0.4)
	return {
		"seed": 7.0,
		"width": width,
		"wall_height": height - rise,
		"rise": rise,
		"length": float(s["tunnel_end_z"]) - float(s["portal_z"]),
		"collapse": s["collapse_length"],
		"lining": TerrainHeights.TRENCH_MARGIN + 0.05,
		"headwall_width": 24.0,
	}


## How wide the headwall must be to hide the step where the cutting meets the slope.
static func headwall_width(heights: TerrainHeights) -> float:
	var portal: float = heights.start["portal_z"]
	var centre := heights.road.x_at(portal)
	var half := float(heights.start["tunnel_half_width"]) + 2.0
	var x := half
	while x < heights.width / 2.0:
		if _step(heights, centre + x, portal) < HEADWALL_MIN_STEP and _step(heights, centre - x, portal) < HEADWALL_MIN_STEP:
			break
		x += 1.0
	return x * 2.0


## How far the cutting in front of the portal lowered the ground at x: the headwall holds
## back that much. (Not the height difference across the portal line: on a steep slope that
## is never small, and the wall ran along the whole hillside.)
static func _step(heights: TerrainHeights, x: float, portal: float) -> float:
	return heights.natural_height(x, portal - 0.6) - heights.height_at(x, portal - 0.6)


## The headwall's height above the floor at local x: just over the higher side of the step.
static func headwall_top(heights: TerrainHeights, floor_y: float) -> Callable:
	var portal: float = heights.start["portal_z"]
	var centre := heights.road.x_at(portal)
	var p := tunnel_params(heights)
	var crown := float(p["wall_height"]) + float(p["rise"]) + float(p["lining"])
	var inner := float(p["width"]) / 2.0 + float(p["lining"])
	return func(x: float) -> float:
		if _step(heights, centre + x, portal) < HEADWALL_MIN_STEP and absf(x) > inner:
			return 0.0
		# The highest ground within a metre either side, so the top steps gently instead of
		# following every voxel of the slope.
		var ground := -INF
		for dx: float in [-1.0, 0.0, 1.0]:
			ground = maxf(ground, maxf(heights.height_at(centre + x + dx, portal + 0.6), heights.natural_height(centre + x + dx, portal - 0.6)))
		var h := snappedf(ground - floor_y + HEADWALL_MARGIN, HEADWALL_STEP)
		return maxf(h, crown + 0.8) if absf(x) <= inner + 0.5 else h


## Rock over the roof: per column, from the roof up to the mountain's surface (never less
## than a thin layer, so the roof is always covered). Collision as one box per metre along,
## up to the lowest point of that slice.
func _cover_profile(heights: TerrainHeights, p: Dictionary, floor_y: float) -> Dictionary:
	var half := float(p["width"]) / 2.0 + float(p["lining"]) + COVER_OVERHANG
	var length: float = p["length"]
	var roof := VoxTunnel.FLOOR + float(p["wall_height"]) + float(p["rise"]) + float(p["lining"])
	var tops: Dictionary[Vector2i, float] = {}
	var boxes: Array[AABB] = []
	var cols := int(ceil(half * 2.0 / COVER_VOXEL))
	var rows := int(ceil(length / COVER_VOXEL))
	var lowest_per_metre: Dictionary[int, float] = {}
	for i in cols:
		for k in rows:
			var lx := -half + (i + 0.5) * COVER_VOXEL
			var lz := -length / 2.0 + (k + 0.5) * COVER_VOXEL
			var ground := heights.natural_height(position.x + lx, position.z + lz) - floor_y + VoxTunnel.FLOOR + COVER_LIFT
			var top := maxf(ground, roof + COVER_VOXEL)
			tops[Vector2i(i, k)] = top
			var metre := int(floor(k * COVER_VOXEL))
			lowest_per_metre[metre] = minf(float(lowest_per_metre.get(metre, INF)), top)
	for metre: int in lowest_per_metre.keys():
		var lz := -length / 2.0 + metre
		boxes.append(AABB(Vector3(-half, roof, lz), Vector3(half * 2.0, lowest_per_metre[metre] - roof, minf(1.0, length - metre))))
	return {"tops": tops, "boxes": boxes, "roof": roof, "half": half}


func _cover_model(p: Dictionary, cover: Dictionary) -> VoxelModel:
	var ground := get_parent().get_node_or_null("Terrain") as VoxelWorld
	var tops: Dictionary = cover["tops"]
	var roof: float = cover["roof"]
	var half: float = cover["half"]
	var length: float = p["length"]
	var highest := roof
	for top: float in tops.values():
		highest = maxf(highest, top)
	var m := VoxGenerator.new_model()
	m.setup(Vector3(half * 2.0 + COVER_VOXEL * 2.0, highest + COVER_VOXEL * 2.0, length + COVER_VOXEL * 2.0), COVER_VOXEL)
	for cell: Vector2i in tops.keys():
		var x := -half + cell.x * COVER_VOXEL
		var z := -length / 2.0 + cell.y * COVER_VOXEL
		var top: float = tops[cell]
		# Coloured like the ground it continues (the ground's voxel tops take its colour and
		# its steps show rock), so it reads as the mountain carrying on rather than a strip.
		m.fill_box(Vector3(x, roof, z), Vector3(x + COVER_VOXEL, top, z + COVER_VOXEL), VoxelWorld.ROCK, 0.0, 3)
		if ground != null:
			var wx := position.x + x + COVER_VOXEL / 2.0
			var wz := position.z + z + COVER_VOXEL / 2.0
			m.paint_box(Vector3(x, top - COVER_VOXEL * 0.5, z), Vector3(x + COVER_VOXEL, top, z + COVER_VOXEL), ground.ground_colour(wx, wz), 0.0, 4)
	return m


func _add_box(body: StaticBody3D, box: AABB) -> void:
	if box.size.x <= 0.0 or box.size.y <= 0.0 or box.size.z <= 0.0:
		return
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = box.size
	shape.shape = b
	shape.position = box.get_center()
	body.add_child(shape)

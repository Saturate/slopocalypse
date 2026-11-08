class_name TerrainHeights
extends RefCounted
## Deterministic terrain height function shared by the runtime terrain, the world builder,
## scenery and spawn logic, so they always agree on where the ground is.
##
## The world is a strip `width` wide and `length` long running along -z, starting `behind`
## metres behind the spawn at the origin. Hills grow and shrink with the road's stages, the
## spawn is flattened, and the ground is levelled under the road.
##
## With a `start` block the world begins at a mountain: a ridge rises behind the spawn and the
## road comes out of it through a tunnel, which is a trench cut down to the road here (the
## height map has no overhangs; StartTunnel builds the lining, roof and rock over it).

const REQUIRED := {
	"width": TYPE_FLOAT,
	"length": TYPE_FLOAT,
	"behind": TYPE_FLOAT,
	"height_amplitude": TYPE_FLOAT,
	"noise_frequency": TYPE_FLOAT,
	"seed": TYPE_FLOAT,
	"flat_radius": TYPE_FLOAT,
	"flat_blend": TYPE_FLOAT,
}

## How much the mountain's height varies (a share of it), and its noise, sampled faster and
## elsewhere than the land's so the two don't line up.
const MOUNTAIN_RUGGED := 0.3
const MOUNTAIN_NOISE_SCALE := 1.7
const MOUNTAIN_NOISE_OFFSET := 500.0
## Metres of craggy detail on the mountain, and how fine it is.
const MOUNTAIN_CRAGS := 8.0
const MOUNTAIN_CRAG_FREQUENCY := 0.035
## The trench is cut this much wider than the tunnel's inside, so its face sits inside the
## lining (StartTunnel) rather than in front of it.
const TRENCH_MARGIN := 0.45

## Keys a `start` block needs; without one there is no mountain or tunnel.
const START_REQUIRED := {
	"portal_z": TYPE_FLOAT,
	"tunnel_end_z": TYPE_FLOAT,
	"tunnel_half_width": TYPE_FLOAT,
	"tunnel_height": TYPE_FLOAT,
	"collapse_length": TYPE_FLOAT,
	"mountain_height": TYPE_FLOAT,
	"mountain_front": TYPE_FLOAT,
	"mountain_back": TYPE_FLOAT,
	"car_distance": TYPE_FLOAT,
	"car_side": TYPE_FLOAT,
}

var width: float
var length: float
var behind: float
var amplitude: float
var flat_radius: float
var flat_blend: float
var stages: RoadStages
## The `start` block, or empty.
var start: Dictionary = {}
## Null when the config has no road.
var road: RoadPath

var _noise := FastNoiseLite.new()
var _crags := FastNoiseLite.new()


func _init(config: Dictionary) -> void:
	width = config["width"]
	length = config["length"]
	behind = config["behind"]
	amplitude = config["height_amplitude"]
	flat_radius = config["flat_radius"]
	flat_blend = config["flat_blend"]
	_noise.seed = int(config["seed"])
	_noise.frequency = config["noise_frequency"]
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_crags.seed = int(config["seed"]) + 77
	_crags.frequency = MOUNTAIN_CRAG_FREQUENCY
	_crags.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_crags.fractal_octaves = 3
	stages = RoadStages.new(config.get("stages", []))
	# Plain key checks, not Data.require: the world builder runs this without autoloads.
	var start_cfg: Variant = config.get("start")
	if start_cfg is Dictionary and (start_cfg as Dictionary).has_all(START_REQUIRED.keys()):
		start = start_cfg
	var road_cfg: Variant = config.get("road")
	if road_cfg is Dictionary and (road_cfg as Dictionary).has_all(RoadPath.REQUIRED.keys()):
		# The road begins at the collapse inside the tunnel and runs through the mountain at
		# the land's height, not over it.
		var road_start := minf(z_max(), float(start["tunnel_end_z"])) if has_tunnel() else z_max()
		road = RoadPath.new(road_cfg, road_start, z_min(), land_height, int(config["seed"]))


## Near end of the world (behind the spawn).
func z_max() -> float:
	return behind


## Far end of the world, where the road ends.
func z_min() -> float:
	return behind - length


## The world's footprint on the ground: x and z.
func extent() -> Rect2:
	return Rect2(-width / 2.0, z_min(), width, length)


## How far down the road a point is, in metres (0 at the spawn).
func distance_along(z: float) -> float:
	return maxf(-z, 0.0)


## The rolling land, without the start mountain.
func land_height(x: float, z: float) -> float:
	var spawn := smoothstep(flat_radius, flat_radius + flat_blend, Vector2(x, z).length())
	var hills := stages.value("hills", distance_along(z), 1.0)
	return _noise.get_noise_2d(x, z) * amplitude * hills * spawn


## The land before the road and the tunnel are cut in.
func natural_height(x: float, z: float) -> float:
	return land_height(x, z) + mountain_height(x, z)


## The ridge the world starts at: it rises steeply just in front of the tunnel portal and
## stays up behind it, rugged rather than a smooth wall.
func mountain_height(x: float, z: float) -> float:
	if start.is_empty():
		return 0.0
	var portal: float = start["portal_z"]
	var rise := smoothstep(portal - float(start["mountain_front"]), portal + float(start["mountain_back"]), z)
	if rise <= 0.0:
		return 0.0
	var rugged := 1.0 + MOUNTAIN_RUGGED * _noise.get_noise_2d(x * MOUNTAIN_NOISE_SCALE + MOUNTAIN_NOISE_OFFSET, z * MOUNTAIN_NOISE_SCALE)
	# Crags and ledges on top of the broad shape, so the face isn't one smooth ramp.
	var crags := _crags.get_noise_2d(x, z) * MOUNTAIN_CRAGS
	return float(start["mountain_height"]) * rise * rugged + crags * rise


func has_tunnel() -> bool:
	return not start.is_empty()


## Inside the tunnel's trench (from the portal to the collapse at its end), widened by
## `margin` on every side.
func in_tunnel(x: float, z: float, margin: float = 0.0) -> bool:
	if start.is_empty():
		return false
	if z < float(start["portal_z"]) - margin or z > float(start["tunnel_end_z"]) + margin:
		return false
	var centre := road.x_at(z) if road != null else 0.0
	return absf(x - centre) < float(start["tunnel_half_width"]) + margin


func _in_trench(x: float, z: float) -> bool:
	if z < float(start["portal_z"]) or z > float(start["tunnel_end_z"]):
		return false
	return absf(x - road.x_at(z)) < float(start["tunnel_half_width"]) + TRENCH_MARGIN


## Height in metres at world x/z.
func height_at(x: float, z: float) -> float:
	var h := natural_height(x, z)
	if road == null:
		return h
	if has_tunnel():
		if _in_trench(x, z):
			return road.height_at(z)
		# The mountain over the tunnel is untouched; the portal's headwall hides the step
		# where the cutting in front of it meets the slope.
		if z > float(start["portal_z"]):
			return h
	var off_road := smoothstep(road.half_width, road.half_width + road.blend, road.distance(x, z))
	return lerpf(road.height_at(z), h, off_road)


## Highest the ground can be anywhere (for skipping voxel blocks that are all air or rock).
func max_amplitude() -> float:
	var most := 1.0
	for d in range(0, int(length) + 1, 50):
		most = maxf(most, stages.value("hills", float(d), 1.0))
	var peak := float(start["mountain_height"]) * (1.0 + MOUNTAIN_RUGGED) + MOUNTAIN_CRAGS if has_tunnel() else 0.0
	return amplitude * most + peak


## The untouched heights as a texture over `extent()`, one texel per `metres_per_texel`,
## for the terrain shader: R is the height (it shows dirt wherever the surface sits below),
## G is 1 on the road, fading to 0 just past its edge (the shader tucks the drawn terrain
## under the road there, so coarse distant terrain never pokes through it).
func bake(metres_per_texel: float) -> ImageTexture:
	var area := extent()
	var w := maxi(int(area.size.x / metres_per_texel), 1)
	var h := maxi(int(area.size.y / metres_per_texel), 1)
	var img := Image.create(w, h, false, Image.FORMAT_RGF)
	for py in h:
		var z := area.position.y + (py + 0.5) * area.size.y / h
		for px in w:
			var x := area.position.x + (px + 0.5) * area.size.x / w
			var on_road := 0.0
			if road != null:
				# Inside the road's own width only, so the dip never bares the road's sides.
				on_road = 1.0 - smoothstep(road.half_width - 2.0, road.half_width - 0.5, road.distance(x, z))
			img.set_pixel(px, py, Color(height_at(x, z), on_road, 0.0))
	return ImageTexture.create_from_image(img)

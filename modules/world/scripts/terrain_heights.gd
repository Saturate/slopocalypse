class_name TerrainHeights
extends RefCounted
## Deterministic terrain height function shared by the runtime terrain, the world builder,
## scenery and spawn logic, so they always agree on where the ground is.
##
## The world is a strip `width` wide and `length` long running along -z, starting `behind`
## metres behind the spawn at the origin. Hills grow and shrink with the road's stages, the
## spawn is flattened, and the ground is levelled under the road.

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

var width: float
var length: float
var behind: float
var amplitude: float
var flat_radius: float
var flat_blend: float
var stages: RoadStages
## Null when the config has no road.
var road: RoadPath

var _noise := FastNoiseLite.new()


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
	stages = RoadStages.new(config.get("stages", []))
	# A plain key check, not Data.require: the world builder runs this without autoloads.
	var road_cfg: Variant = config.get("road")
	if road_cfg is Dictionary and (road_cfg as Dictionary).has_all(RoadPath.REQUIRED.keys()):
		road = RoadPath.new(road_cfg, z_max(), z_min(), natural_height, int(config["seed"]))


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


## The land before the road is cut in.
func natural_height(x: float, z: float) -> float:
	var spawn := smoothstep(flat_radius, flat_radius + flat_blend, Vector2(x, z).length())
	var hills := stages.value("hills", distance_along(z), 1.0)
	return _noise.get_noise_2d(x, z) * amplitude * hills * spawn


## Height in metres at world x/z.
func height_at(x: float, z: float) -> float:
	var h := natural_height(x, z)
	if road == null:
		return h
	var off_road := smoothstep(road.half_width, road.half_width + road.blend, road.distance(x, z))
	return lerpf(road.height_at(z), h, off_road)


## Highest the ground can be anywhere (for skipping voxel blocks that are all air or rock).
func max_amplitude() -> float:
	var most := 1.0
	for d in range(0, int(length) + 1, 50):
		most = maxf(most, stages.value("hills", float(d), 1.0))
	return amplitude * most


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
				on_road = 1.0 - smoothstep(road.half_width, road.half_width + metres_per_texel * 1.5, road.distance(x, z))
			img.set_pixel(px, py, Color(height_at(x, z), on_road, 0.0))
	return ImageTexture.create_from_image(img)

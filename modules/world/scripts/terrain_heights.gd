class_name TerrainHeights
extends RefCounted
## Deterministic terrain height function shared by the runtime terrain, the world builder
## (cover placement) and spawn logic, so they always agree on where the ground is.

const REQUIRED := {
	"size": TYPE_FLOAT,
	"resolution": TYPE_FLOAT,
	"height_amplitude": TYPE_FLOAT,
	"noise_frequency": TYPE_FLOAT,
	"seed": TYPE_FLOAT,
	"flat_radius": TYPE_FLOAT,
	"flat_blend": TYPE_FLOAT,
}

var size: float
var resolution: int
var amplitude: float
var flat_radius: float
var flat_blend: float

var _noise := FastNoiseLite.new()


func _init(config: Dictionary) -> void:
	size = config["size"]
	resolution = int(config["resolution"])
	amplitude = config["height_amplitude"]
	flat_radius = config["flat_radius"]
	flat_blend = config["flat_blend"]
	_noise.seed = int(config["seed"])
	_noise.frequency = config["noise_frequency"]
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH


## Height in metres at world x/z. Flattened around the origin so spawns are level.
func height_at(x: float, z: float) -> float:
	var distance := Vector2(x, z).length()
	var blend := smoothstep(flat_radius, flat_radius + flat_blend, distance)
	return _noise.get_noise_2d(x, z) * amplitude * blend


## The untouched heights as a float texture covering the world, `res` texels a side, for
## the terrain shader (it shows dirt wherever the surface sits below these).
func bake(res: int) -> ImageTexture:
	var img := Image.create(res, res, false, Image.FORMAT_RF)
	var half := size / 2.0
	for py in res:
		for px in res:
			var x := -half + (px + 0.5) * size / res
			var z := -half + (py + 0.5) * size / res
			img.set_pixel(px, py, Color(height_at(x, z), 0.0, 0.0))
	return ImageTexture.create_from_image(img)


func spacing() -> float:
	return size / float(resolution - 1)

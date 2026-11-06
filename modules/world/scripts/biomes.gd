class_name Biomes
extends RefCounted
## Seeded biome fields shared by scenery placement and the terrain shader, so server and
## clients agree on where forests, meadows and rocky ground are. Each field is 0..1:
##   forest: tree density (dense woods with clearings and open meadows between)
##   dry:    yellowed grass and bare patches
##   rock:   boulders and exposed rock on gentle ground

const REQUIRED := {"seed": TYPE_FLOAT, "forest_frequency": TYPE_FLOAT, "forest_threshold": TYPE_FLOAT, "dry_frequency": TYPE_FLOAT, "rock_frequency": TYPE_FLOAT, "rock_threshold": TYPE_FLOAT, "map_resolution": TYPE_FLOAT}

var _forest := FastNoiseLite.new()
var _dry := FastNoiseLite.new()
var _rock := FastNoiseLite.new()
var _forest_threshold: float
var _rock_threshold: float
var _map_resolution: int


func _init(config: Dictionary) -> void:
	var s := int(config["seed"])
	for n: FastNoiseLite in [_forest, _dry, _rock]:
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_octaves = 3
	_forest.seed = s
	_forest.frequency = config["forest_frequency"]
	_dry.seed = s + 101
	_dry.frequency = config["dry_frequency"]
	_rock.seed = s + 202
	_rock.frequency = config["rock_frequency"]
	_forest_threshold = config["forest_threshold"]
	_rock_threshold = config["rock_threshold"]
	_map_resolution = int(config["map_resolution"])


## 0 in open meadow, ramping to 1 in the middle of a forest; edges blend over a band so
## forests thin out instead of stopping at a line.
func forest(x: float, z: float) -> float:
	var n := _forest.get_noise_2d(x, z) * 0.5 + 0.5
	return smoothstep(_forest_threshold - 0.08, _forest_threshold + 0.12, n)


func dry(x: float, z: float) -> float:
	var n := _dry.get_noise_2d(x, z) * 0.5 + 0.5
	# Forests stay moist; dryness lives in the open.
	return smoothstep(0.5, 0.75, n) * (1.0 - forest(x, z))


func rock(x: float, z: float) -> float:
	var n := _rock.get_noise_2d(x, z) * 0.5 + 0.5
	return smoothstep(_rock_threshold, _rock_threshold + 0.15, n)


## Bakes the fields into a texture covering the world (R forest, G dry, B rock) for the
## terrain shader. One texel per `size / resolution` metres.
func bake(size: float) -> ImageTexture:
	var res := _map_resolution
	var img := Image.create(res, res, false, Image.FORMAT_RGB8)
	var half := size / 2.0
	for py in res:
		for px in res:
			var x := -half + (px + 0.5) * size / res
			var z := -half + (py + 0.5) * size / res
			img.set_pixel(px, py, Color(forest(x, z), dry(x, z), rock(x, z)))
	return ImageTexture.create_from_image(img)

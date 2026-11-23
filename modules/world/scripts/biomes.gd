class_name Biomes
extends GroundBiomes
## Seeded biome noise fields, which WorldLand shapes by the land, so server and clients agree
## on where forests, meadows and rocky ground are. Each field is 0..1:
##   forest: tree density (dense woods with clearings and open meadows between)
##   dry:    yellowed grass and bare patches
##   rock:   boulders and exposed rock on gentle ground

var _forest := FastNoiseLite.new()
var _dry := FastNoiseLite.new()
var _rock := FastNoiseLite.new()
var _forest_threshold: float
var _rock_threshold: float


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


## 0 in open meadow, ramping to 1 in the middle of a forest; edges blend over a band so
## forests thin out instead of stopping at a line.
func forest(x: float, z: float) -> float:
	var n := _forest.get_noise_2d(x, z) * 0.5 + 0.5
	return smoothstep(_forest_threshold - 0.08, _forest_threshold + 0.12, n)


func dry(x: float, z: float) -> float:
	var n := _dry.get_noise_2d(x, z) * 0.5 + 0.5
	# Forests stay moist; dryness lives in the open.
	return clampf(smoothstep(0.5, 0.75, n) + 0.25, 0.0, 1.0) * (1.0 - forest(x, z))


func rock(x: float, z: float) -> float:
	var n := _rock.get_noise_2d(x, z) * 0.5 + 0.5
	return clampf(smoothstep(_rock_threshold, _rock_threshold + 0.15, n) + 0.15, 0.0, 1.0)


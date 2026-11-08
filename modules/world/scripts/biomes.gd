class_name Biomes
extends RefCounted
## Seeded biome fields shared by scenery placement and the terrain shader, so server and
## clients agree on where forests, meadows and rocky ground are. Each field is 0..1:
##   forest: tree density (dense woods with clearings and open meadows between)
##   dry:    yellowed grass and bare patches
##   rock:   boulders and exposed rock on gentle ground

const REQUIRED := {"seed": TYPE_FLOAT, "forest_frequency": TYPE_FLOAT, "forest_threshold": TYPE_FLOAT, "dry_frequency": TYPE_FLOAT, "rock_frequency": TYPE_FLOAT, "rock_threshold": TYPE_FLOAT, "map_metres_per_texel": TYPE_FLOAT}

var _forest := FastNoiseLite.new()
var _dry := FastNoiseLite.new()
var _rock := FastNoiseLite.new()
var _forest_threshold: float
var _rock_threshold: float
var _stages: RoadStages


## `stages` shifts the fields with distance down the road (forest early, dry and rock later).
func _init(config: Dictionary, stages: RoadStages = null) -> void:
	_stages = stages if stages != null else RoadStages.new()
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
	return _staged(smoothstep(_forest_threshold - 0.08, _forest_threshold + 0.12, n), "forest", z)


func dry(x: float, z: float) -> float:
	var n := _dry.get_noise_2d(x, z) * 0.5 + 0.5
	# Forests stay moist; dryness lives in the open.
	return _staged(smoothstep(0.5, 0.75, n) + 0.25, "dry", z) * (1.0 - forest(x, z))


func rock(x: float, z: float) -> float:
	var n := _rock.get_noise_2d(x, z) * 0.5 + 0.5
	return _staged(smoothstep(_rock_threshold, _rock_threshold + 0.15, n) + 0.15, "rock", z)


## A noise field scaled by its stage weight: a weight of 1 keeps (and slightly boosts) the
## field, 0 removes it.
func _staged(field: float, key: String, z: float) -> float:
	var w := _stages.value(key, maxf(-z, 0.0), 1.0)
	return clampf(field * (0.4 + w) - (1.0 - w) * 0.3, 0.0, 1.0)


## Bakes the fields into a texture over `area` (x, z on the ground; R forest, G dry, B rock)
## for the terrain shader, one texel per `metres_per_texel`.
func bake(area: Rect2, metres_per_texel: float) -> ImageTexture:
	var w := maxi(int(area.size.x / metres_per_texel), 1)
	var h := maxi(int(area.size.y / metres_per_texel), 1)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for py in h:
		var z := area.position.y + (py + 0.5) * area.size.y / h
		for px in w:
			var x := area.position.x + (px + 0.5) * area.size.x / w
			img.set_pixel(px, py, Color(forest(x, z), dry(x, z), rock(x, z)))
	return ImageTexture.create_from_image(img)

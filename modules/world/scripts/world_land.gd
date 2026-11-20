class_name WorldLand
extends RefCounted
## The land of a map built from a recipe (#427, decision 0010): height from layered noise
## over a square round the origin. A broad base swells gently everywhere; the hill layers
## only rise where a slow hill mask says this is hilly country, so between them lie wide
## stretches of near-flat lowland for towns, farms and roads. Pure and seeded: the same recipe
## and seed give the same land on every machine. Read-only after it is built, so worker
## threads may sample it at once. No autoloads: builders and tools use it too.

var size := 0.0
var relief := 0.0

var _layers: Array[FastNoiseLite] = []
var _weights: Array[float] = []
var _masked: Array[bool] = []
var _scale := 1.0
var _mask := FastNoiseLite.new()
var _mask_from := 0.0
var _mask_to := 1.0


func _init(recipe: Dictionary, seed_value: int) -> void:
	size = float(recipe["size"])
	relief = float(recipe["relief"])
	var mask: Dictionary = recipe["hill_mask"]
	_mask.seed = seed_value * 7919 + 31337
	_mask.frequency = float(mask["frequency"])
	_mask.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mask.fractal_octaves = 2
	_mask_from = float(mask["from"])
	_mask_to = float(mask["to"])
	var total := 0.0
	var layers: Array = recipe["layers"]
	for i in layers.size():
		var layer: Dictionary = layers[i]
		var noise := FastNoiseLite.new()
		# Each layer its own seed, so layers don't line up.
		noise.seed = seed_value * 7919 + i * 104729
		noise.frequency = float(layer["frequency"])
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.fractal_octaves = int(layer.get("octaves", 1))
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_layers.append(noise)
		_weights.append(float(layer["amplitude"]))
		_masked.append(bool(layer.get("masked", false)))
		total += absf(float(layer["amplitude"]))
	# Layers sum to at most ±1 before the relief scales them.
	_scale = 1.0 / total if total > 0.0 else 1.0


## The map's footprint on the ground: x and z.
func bounds() -> Rect2:
	return Rect2(-size / 2.0, -size / 2.0, size, size)


## Height of the land at (x, z), in metres.
func height(x: float, z: float) -> float:
	var hilly := hilliness(x, z)
	var t := 0.0
	for i in _layers.size():
		if not _masked[i]:
			t += _layers[i].get_noise_2d(x, z) * _weights[i]
		elif hilly > 0.0:
			# Hills rise out of the lowland, never sink below it.
			t += (_layers[i].get_noise_2d(x, z) * 0.5 + 0.5) * _weights[i] * hilly
	return clampf(t * _scale, -1.0, 1.0) * relief * 0.5


## 0 in lowland, rising to 1 in hilly country: where the hill layers count.
func hilliness(x: float, z: float) -> float:
	return smoothstep(_mask_from, _mask_to, _mask.get_noise_2d(x, z))


## Share of the map, sampled every `step` metres, where the ground rises less than
## `max_grade` metres per metre.
func walkable_share(step: float, max_grade: float) -> float:
	var b := bounds()
	var good := 0
	var all := 0
	var x := b.position.x
	while x < b.end.x - step:
		var z := b.position.y
		while z < b.end.y - step:
			var h := height(x, z)
			var grade := Vector2(height(x + step, z) - h, height(x, z + step) - h).length() / step
			if grade < max_grade:
				good += 1
			all += 1
			z += step
		x += step
	return float(good) / float(all) if all > 0 else 0.0

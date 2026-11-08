class_name RoadPath
extends RefCounted
## The one road: where it runs and how high it sits, sampled every metre along z when the
## world loads, so lookups are two array reads (the terrain generator asks for every voxel
## column, on worker threads).
##
## It runs along -z from behind the spawn to the far end, starting `offset` metres to the
## side of the spawn and wandering from side to side once it is clear of it. Its elevation
## follows the land, smoothed and held to `max_grade` so the car never meets a wall.

const REQUIRED := {"offset": TYPE_FLOAT, "half_width": TYPE_FLOAT, "blend": TYPE_FLOAT, "wander": TYPE_FLOAT, "wander_frequency": TYPE_FLOAT, "smoothing": TYPE_FLOAT, "max_grade": TYPE_FLOAT}

var half_width: float
var blend: float
var _z_start: float
var _xs := PackedFloat32Array()
var _ys := PackedFloat32Array()


## `natural` is the land height before the road, `(x, z) -> float`.
func _init(config: Dictionary, z_start: float, z_end: float, natural: Callable, seed: int) -> void:
	half_width = config["half_width"]
	blend = config["blend"]
	_z_start = z_start
	var noise := FastNoiseLite.new()
	noise.seed = seed + 303
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = config["wander_frequency"]
	var count := int(ceil(z_start - z_end)) + 1
	_xs.resize(count)
	var raw := PackedFloat32Array()
	raw.resize(count)
	var wander: float = config["wander"]
	var offset: float = config["offset"]
	for i in count:
		var z := z_start - i
		# Straight past the spawn, then free to wander.
		var free := smoothstep(0.0, 150.0, -z)
		var x := offset + noise.get_noise_1d(z) * wander * free
		_xs[i] = x
		raw[i] = float(natural.call(x, z))
	_ys = _limit_grade(_smooth(raw, int(config["smoothing"])), config["max_grade"])


## Moving average over `window` metres, from prefix sums so it stays linear in length.
static func _smooth(values: PackedFloat32Array, window: int) -> PackedFloat32Array:
	var n := values.size()
	var sums := PackedFloat64Array()
	sums.resize(n + 1)
	for i in n:
		sums[i + 1] = sums[i] + values[i]
	var half := maxi(int(window / 2.0), 1)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var a := maxi(i - half, 0)
		var b := mini(i + half + 1, n)
		out[i] = float((sums[b] - sums[a]) / (b - a))
	return out


## No metre may climb or drop more than `grade`: where the land is steeper, the road cuts
## in or rides an embankment. A pass each way keeps it symmetric.
static func _limit_grade(values: PackedFloat32Array, grade: float) -> PackedFloat32Array:
	var out := values.duplicate()
	for i in range(1, out.size()):
		out[i] = clampf(out[i], out[i - 1] - grade, out[i - 1] + grade)
	for i in range(out.size() - 2, -1, -1):
		out[i] = clampf(out[i], out[i + 1] - grade, out[i + 1] + grade)
	return out


func _sample(values: PackedFloat32Array, z: float) -> float:
	var f := clampf(_z_start - z, 0.0, values.size() - 1.0)
	var i := int(f)
	var j := mini(i + 1, values.size() - 1)
	return lerpf(values[i], values[j], f - i)


func x_at(z: float) -> float:
	return _sample(_xs, z)


func height_at(z: float) -> float:
	return _sample(_ys, z)


## Sideways distance from the centre line; good enough for a road that bends gently.
func distance(x: float, z: float) -> float:
	return absf(x - x_at(z))

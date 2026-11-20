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

# Water (see `_find_ponds`): a grid every `_cell` metres over the map, each point the index of
# the pond it lies in or -1.
var _cell := 16.0
var _side := 0
var _pond_of := PackedInt32Array()
var _ponds: Array[Dictionary] = []
var _deepen := 1.0


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
	var water: Variant = recipe.get("water")
	if water is Dictionary:
		_find_ponds(water)


## The map's footprint on the ground: x and z.
func bounds() -> Rect2:
	return Rect2(-size / 2.0, -size / 2.0, size, size)


## Height of the ground at (x, z), in metres: pond beds included.
func height(x: float, z: float) -> float:
	var h := land_height(x, z)
	var level := _level_over(x, z, h)
	# A pond's bed goes `deepen` times as far under its water as the land would.
	return h if is_nan(level) else level - (level - h) * _deepen


## The water's surface at (x, z), or NAN on dry land.
func water_level(x: float, z: float) -> float:
	return _level_over(x, z, land_height(x, z))


## The ponds: each {level, centre (its deepest point, x and z), area (square metres), depth
## (metres at its deepest, before the bed is deepened)}.
func ponds() -> Array[Dictionary]:
	return _ponds


## Height of the land before water: the noise alone.
func land_height(x: float, z: float) -> float:
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


## The level of the pond over (x, z) whose land is `h` there, or NAN.
func _level_over(x: float, z: float, h: float) -> float:
	if _ponds.is_empty():
		return NAN
	var b := bounds()
	var gx := (x - b.position.x) / _cell
	var gz := (z - b.position.y) / _cell
	# Any of the four grid points round it: the shore follows the land, not the grid.
	for dx in 2:
		for dz in 2:
			var i := clampi(floori(gx) + dx, 0, _side - 1)
			var j := clampi(floori(gz) + dz, 0, _side - 1)
			var pond := _pond_of[j * _side + i]
			if pond >= 0 and h < float(_ponds[pond]["level"]):
				return float(_ponds[pond]["level"])
	return NAN


## Where water would collect: the land surveyed on a grid, every depression filled to the
## level it would spill at (a priority flood from the map's edge), and each basin deep and
## large enough kept as a pond, its level `freeboard` under the spill and lowered until it is
## no larger than `max_area`.
func _find_ponds(water: Dictionary) -> void:
	_cell = float(water["cell"])
	_deepen = float(water["deepen"])
	_side = int(ceil(size / _cell)) + 1
	var n := _side * _side
	var b := bounds()
	var ground := PackedFloat32Array()
	ground.resize(n)
	for j in _side:
		for i in _side:
			ground[j * _side + i] = land_height(b.position.x + i * _cell, b.position.y + j * _cell)
	var filled := PackedFloat32Array()
	filled.resize(n)
	var seen := PackedByteArray()
	seen.resize(n)
	var heap := _Heap.new()
	for j in _side:
		for i in _side:
			if i == 0 or j == 0 or i == _side - 1 or j == _side - 1:
				var k := j * _side + i
				filled[k] = ground[k]
				seen[k] = 1
				heap.push(ground[k], k)
	while not heap.is_empty():
		var k := heap.pop()
		var i := k % _side
		var j := k / _side
		for d: Vector2i in NEIGHBOURS:
			var ni := i + d.x
			var nj := j + d.y
			if ni < 0 or nj < 0 or ni >= _side or nj >= _side:
				continue
			var nk := nj * _side + ni
			if seen[nk] == 1:
				continue
			seen[nk] = 1
			filled[nk] = maxf(ground[nk], filled[k])
			heap.push(filled[nk], nk)
	_pond_of.resize(n)
	_pond_of.fill(-1)
	var label := PackedInt32Array()
	label.resize(n)
	label.fill(-1)
	var min_depth := float(water["min_depth"])
	var cell_area := _cell * _cell
	for start in n:
		if label[start] >= 0 or filled[start] - ground[start] < 0.05:
			continue
		# One basin: the cells under water when it is filled to the brim.
		var basin: Array[int] = []
		var stack: Array[int] = [start]
		label[start] = start
		while not stack.is_empty():
			var k: int = stack.pop_back()
			basin.append(k)
			for d: Vector2i in NEIGHBOURS:
				var ni := k % _side + d.x
				var nj := k / _side + d.y
				if ni < 0 or nj < 0 or ni >= _side or nj >= _side:
					continue
				var nk := nj * _side + ni
				if label[nk] < 0 and filled[nk] - ground[nk] >= 0.05:
					label[nk] = start
					stack.append(nk)
		var deepest := basin[0]
		var brim := -INF
		for k in basin:
			brim = maxf(brim, filled[k])
			if ground[k] < ground[deepest]:
				deepest = k
		var level := brim - float(water["freeboard"])
		# Too big: lower the water until it fits.
		var low := ground[deepest]
		var high := level
		for step in 24:
			if _cells_under(basin, ground, level) * cell_area <= float(water["max_area"]):
				break
			high = level
			level = (low + high) / 2.0
		var wet: Array[int] = []
		for k in basin:
			if ground[k] < level:
				wet.append(k)
		var area := wet.size() * cell_area
		var depth := level - ground[deepest]
		if depth < min_depth or area < float(water["min_area"]) or area > float(water["max_area"]):
			continue
		var id := _ponds.size()
		for k in wet:
			_pond_of[k] = id
		_ponds.append({"level": level, "area": area, "depth": depth,
			"centre": Vector2(b.position.x + (deepest % _side) * _cell, b.position.y + (deepest / _side) * _cell)})


func _cells_under(cells: Array[int], ground: PackedFloat32Array, level: float) -> int:
	var count := 0
	for k in cells:
		if ground[k] < level:
			count += 1
	return count


const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## A min-heap of (key, value) for the priority flood.
class _Heap:
	var _keys := PackedFloat32Array()
	var _values := PackedInt32Array()

	func is_empty() -> bool:
		return _keys.is_empty()

	func push(key: float, value: int) -> void:
		_keys.append(key)
		_values.append(value)
		var i := _keys.size() - 1
		while i > 0:
			var parent := (i - 1) / 2
			if _keys[parent] <= _keys[i]:
				break
			_swap(i, parent)
			i = parent

	## The value with the smallest key, taken off.
	func pop() -> int:
		var top := _values[0]
		var last := _keys.size() - 1
		_swap(0, last)
		_keys.resize(last)
		_values.resize(last)
		var i := 0
		while true:
			var smallest := i
			for c in [2 * i + 1, 2 * i + 2]:
				if c < _keys.size() and _keys[c] < _keys[smallest]:
					smallest = c
			if smallest == i:
				break
			_swap(i, smallest)
			i = smallest
		return top

	func _swap(a: int, b: int) -> void:
		var k := _keys[a]
		_keys[a] = _keys[b]
		_keys[b] = k
		var v := _values[a]
		_values[a] = _values[b]
		_values[b] = v

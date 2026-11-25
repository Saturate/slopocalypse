class_name WorldLand
extends RefCounted
## The land of a map built from a recipe (#427, decision 0010): height from layered noise
## over a square round the origin. A broad base swells gently everywhere; the hill layers
## only rise where a slow hill mask says this is hilly country, so between them lie wide
## stretches of near-flat lowland for towns, farms and roads. A recipe with a `coast` (#454)
## makes the map an island: the land falls under the sea towards the edge along a noisy
## coastline, lowland settling to beaches and hills ending in low cliffs, with a few islets
## offshore. Pure and seeded: the same recipe
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

# The coast (see `_coast_height`): NAN sea level on a map without one.
var sea_level := NAN
var _radius := 0.0
var _roundness := 4.0
var _coast_noise := FastNoiseLite.new()
var _coast_amplitude := 0.0
var _seabed := 0.0
var _edge := 0.0
var _inland := 1.0
var _beach_rise := 0.0
var _beach_sea := 1.0
var _beach_land := 1.0
var _cliff_rise := 0.0
var _cliff_sea := 1.0
var _cliff_land := 1.0
var _cliff_inland := 1.0
## Metres in from the coastline past which the coast shapes nothing.
var _reach_in := 0.0
var _cliff_from := 0.0
var _cliff_to := 1.0
var _islets := FastNoiseLite.new()
var _islet_threshold := 1.0
var _islet_near := 0.0
var _islet_far := 0.0
var _islet_rise := 0.0
var _sand_grade := 0.0
var _sand_wash := 0.0
var _sand_height := 0.0
## Per water grid point, 1 where the sea reaches it: below sea level and joined to the map's
## edge under water.
var _sea_of := PackedByteArray()

# Biomes (see `forest`, `dry`, `rock`): the noise fields, then shaped by the land.
var _biomes: Biomes
var _rock_from := 1.0
var _rock_to := 2.0
var _hill_forest := 0.0
var _lowland_forest := 1.0
var _rock_patches := FastNoiseLite.new()
var _dry := FastNoiseLite.new()
var _woodland := FastNoiseLite.new()


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
	var coast: Variant = recipe.get("coast")
	if coast is Dictionary:
		_read_coast(coast, seed_value)
	var water: Variant = recipe.get("water")
	if water is Dictionary:
		_find_ponds(water)
	elif has_coast():
		# No ponds, but the sea is still found on a survey grid.
		_side = int(ceil(size / _cell)) + 1
		_find_sea(_survey())
	var biomes: Variant = recipe.get("biomes")
	if biomes is Dictionary:
		var cfg: Dictionary = (biomes as Dictionary).duplicate()
		cfg["seed"] = float(seed_value * 7919 + 4241)
		_biomes = Biomes.new(cfg)
		_rock_from = float(cfg["rock_grade_from"])
		_rock_to = float(cfg["rock_grade_to"])
		_hill_forest = float(cfg["hill_forest"])
		_lowland_forest = float(cfg["lowland_forest"])
		_rock_patches.seed = seed_value * 7919 + 9001
		_rock_patches.frequency = float(cfg["rock_patch_frequency"])
		_rock_patches.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_rock_patches.fractal_octaves = 2
		_woodland.seed = seed_value * 7919 + 2203
		_woodland.frequency = float(cfg["woodland_frequency"])
		_woodland.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_woodland.fractal_octaves = 1
		_dry.seed = seed_value * 7919 + 6007
		_dry.frequency = float(cfg["dry_frequency"])
		_dry.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_dry.fractal_octaves = 2


## The map's footprint on the ground: x and z.
func bounds() -> Rect2:
	return Rect2(-size / 2.0, -size / 2.0, size, size)


## Height of the ground at (x, z), in metres: pond beds included.
func height(x: float, z: float) -> float:
	return _height_of(x, z, land_height(x, z))


## `height` at (x, z) from its land height `h`, for callers that have it already.
func _height_of(x: float, z: float, h: float) -> float:
	var level := _level_over(x, z, h)
	# A pond's bed goes `deepen` times as far under its water as the land would.
	return h if is_nan(level) or _is_sea_over(x, z, h) else level - (level - h) * _deepen


## The water's surface at (x, z), or NAN on dry land: a pond's level or the sea's.
func water_level(x: float, z: float) -> float:
	var h := land_height(x, z)
	if _is_sea_over(x, z, h):
		return sea_level
	return _level_over(x, z, h)


## Whether the map has a coast: an island in the sea.
func has_coast() -> bool:
	return not is_nan(sea_level)


## Whether (x, z) is under the sea (not a pond, nor land below sea level the sea can't reach).
func is_sea(x: float, z: float) -> bool:
	return has_coast() and _is_sea_over(x, z, land_height(x, z))


## How far (x, z) lies in from the coastline the noise draws, metres (negative out at sea).
## The shore itself falls within a band of it either side, set by how steep the land meets
## the water: see `_coast_height`.
func inland(x: float, z: float) -> float:
	if not has_coast():
		return INF
	var p := pow(pow(absf(x), _roundness) + pow(absf(z), _roundness), 1.0 / _roundness)
	var s := _radius - p + _coast_noise.get_noise_2d(x, z) * _coast_amplitude
	# Open sea at least `edge` metres wide all round, eased in so a headland near the edge
	# rounds off instead of being cut straight.
	var to_edge := size / 2.0 - maxf(absf(x), absf(z)) - _edge
	var k := EDGE_EASE
	var t := maxf(k - absf(s - to_edge), 0.0) / k
	return minf(s, to_edge) - t * t * k / 4.0


## Sand, 0 to 1: beaches on gentle ground just over the sea and the sea floor under it, along
## the coast, and within `wash` metres of the sea on any ground short of rock; none where the
## shore is steep (rock and cliffs, see `rock`). 0 on a map without a coast.
## `slope` as for `rock`.
func sand(x: float, z: float, slope := NAN) -> float:
	# Only along the coast (a low hollow inland is no beach), and that is cheaper to rule out
	# than the height.
	if not has_coast() or inland(x, z) > _beach_land:
		return 0.0
	var above := land_height(x, z) - sea_level
	if above > _sand_height:
		return 0.0
	var g := grade(x, z) if is_nan(slope) else slope
	var gentle := 1.0 - smoothstep(_sand_grade * 0.6, _sand_grade, g)
	var beach := gentle * (1.0 - smoothstep(_sand_height * 0.5, _sand_height, above))
	# Where the ground steepens into the water it is too steep for a beach but not yet rock:
	# sand fades out just as `rock` fades in, so no grass runs down to the sea between them.
	var washed := (1.0 - smoothstep(_rock_from, _rock_to, g)) * (1.0 - smoothstep(_sand_wash * 0.5, _sand_wash, above))
	return maxf(beach, washed)


## The ponds: each {level, centre (its deepest point, x and z), area (square metres), depth
## (metres at its deepest, before the bed is deepened)}.
func ponds() -> Array[Dictionary]:
	return _ponds


## The survey points (x, z) under pond `i`'s water.
func pond_points(i: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var b := bounds()
	for k in _pond_of.size():
		if _pond_of[k] == i:
			out.append(b.position + Vector2(k % _side, k / _side) * _cell)
	return out


## Rise per metre of the ground at (x, z).
func grade(x: float, z: float) -> float:
	var d := GRADE_STEP
	return Vector2(height(x + d, z) - height(x - d, z), height(x, z + d) - height(x, z - d)).length() / (2.0 * d)


## 0 in the open, 1 deep in woods. Woods grow on the hills (`hill_forest` of the way) and in
## a few broad woodland regions out on the lowland (`lowland_forest` at most), so the
## lowland is mostly open fields; the forest field then cuts clearings into them. None in
## water.
func forest(x: float, z: float) -> float:
	if _biomes == null:
		return 0.0
	var h := land_height(x, z)
	if _is_sea_over(x, z, h) or not is_nan(_level_over(x, z, h)):
		return 0.0
	# Nothing grows on a beach.
	if has_coast() and h - sea_level < _sand_height and sand(x, z) > 0.5:
		return 0.0
	var region := smoothstep(0.15, 0.55, _woodland.get_noise_2d(x, z)) * _lowland_forest
	var woody := maxf(hilliness(x, z) * _hill_forest, region)
	var clearings := smoothstep(0.0, 0.75, _biomes.forest(x, z))
	var woods := clampf(woody * clearings * 1.25, 0.0, 1.0)
	# Nor on a cliff over the sea: its face is bare rock, not leaf litter.
	if woods > 0.0 and has_coast() and h - sea_level < _cliff_rise * 2.0:
		woods *= 1.0 - _cliff_at(x, z, h, NAN)
	return woods


## Yellowed grass and bare patches, 0 to 1: patches out in the open that fade softly into
## the meadow, none in the woods.
## `woods` is forest(x, z) when the caller has it already (NAN: worked out here).
func dry(x: float, z: float, woods := NAN) -> float:
	if _biomes == null:
		return 0.0
	return smoothstep(DRY_FROM, DRY_TO, _dry.get_noise_2d(x, z)) * (1.0 - (forest(x, z) if is_nan(woods) else woods))


## Boulders and bare rock, 0 to 1: the rock field (half as much out on the lowland, which is
## fields and meadow), and on steep ground in the heart of the hills rock in patches
## (outcrops and scree, not an even band along every ridge).
## `slope` is grade(x, z) when the caller has it already (NAN: worked out here, which costs
## four height samples).
func rock(x: float, z: float, slope := NAN) -> float:
	if _biomes == null:
		return 0.0
	var hilly := hilliness(x, z)
	var field := _biomes.rock(x, z) * lerpf(0.5, 1.0, hilly)
	var patches := smoothstep(-0.15, 0.3, _rock_patches.get_noise_2d(x, z))
	var steep := smoothstep(_rock_from, _rock_to, grade(x, z) if is_nan(slope) else slope)
	var crag := steep * smoothstep(0.25, 0.75, hilly)
	var bare := maxf(field, crag * patches)
	if has_coast() and steep > 0.0:
		bare = maxf(bare, _shore_rock(land_height(x, z) - sea_level, steep))
	return bare


## Bare rock where steep ground meets the sea, 0 to 1: cliffs and scree all along the shore,
## never grass or woods down to the water. 0 on a map without a coast.
## `slope` as for `rock`.
func cliff(x: float, z: float, slope := NAN) -> float:
	if not has_coast() or _biomes == null:
		return 0.0
	return _cliff_at(x, z, NAN, slope)


## `cliff` with the land height `h` at (x, z) when the caller has it (NAN: worked out here).
## The coast band and then the height rule most ground out before the grade (four more height
## samples) is needed: this runs for every colour the ground is drawn with.
func _cliff_at(x: float, z: float, h: float, slope: float) -> float:
	if inland(x, z) > _beach_land:
		return 0.0
	var above := (land_height(x, z) if is_nan(h) else h) - sea_level
	if above >= _cliff_rise * 2.0:
		return 0.0
	return _shore_rock(above, smoothstep(_rock_from, _rock_to, grade(x, z) if is_nan(slope) else slope))


## `cliff` for ground `steep` (0 to 1, from the rock grades) `above` metres over the sea: all
## of it up to the cliff tops, fading out above them.
func _shore_rock(above: float, steep: float) -> float:
	return steep * (1.0 - smoothstep(_cliff_rise, _cliff_rise * 2.0, above))


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
	var h := clampf(t * _scale, -1.0, 1.0) * relief * 0.5
	return _coast_height(x, z, h, hilly) if has_coast() else h


## The land `h` (at `hilly`) as the coast shapes it: lowland settles towards a beach just over
## the sea within `inland` metres of the coastline, and
## hills keep their height until
## `cliff.inland` metres from it, then come down to the top of a low cliff;
## across the shore the ground falls to the sea floor, gently over a wide band where it was
## lowland (a beach running out into shallows) and over a narrow one under hills (a cliff
## into deep water). Islets rise out of the sea a little way off the coast.
func _coast_height(x: float, z: float, h: float, hilly: float) -> float:
	var s := inland(x, z)
	# Far enough in, the coast changes nothing (the bands and the floor all end by then).
	if s >= _reach_in:
		return h
	var cliff := smoothstep(_cliff_from, _cliff_to, hilly)
	# Lowland near the coast never sinks under the sea: within `inland` of it the land eases
	# onto a floor just over it, so a low stretch there is a plain by the shore, not dry
	# ground below the sea beside it. Further in a hollow keeps its depth (and its pond).
	var floor_level := sea_level + _beach_rise
	var low := h - floor_level
	var floored := floor_level + (low + sqrt(low * low + FLOOR_EASE * FLOOR_EASE)) * 0.5
	h = lerpf(h, maxf(h, floored), 1.0 - smoothstep(_inland * 0.5, _inland, s))
	var near := 1.0 - smoothstep(0.0, lerpf(_inland, _cliff_inland, cliff), s)
	# A cliff's top rises and falls along the coast instead of running level.
	var cliff_top := _cliff_rise * (0.5 + _islets.get_noise_2d(x * CLIFF_WOBBLE, z * CLIFF_WOBBLE) * 0.5 + 0.5)
	h = lerpf(h, sea_level + lerpf(_beach_rise, cliff_top, cliff), near)
	var ground := lerpf(_seabed, h, smoothstep(-lerpf(_beach_sea, _cliff_sea, cliff), lerpf(_beach_land, _cliff_land, cliff), s))
	if s < -_islet_near and s > -_islet_far:
		# Only in a ring off the coast, fading in and out at its edges, so an islet stands
		# apart from the island and never far out at the map's edge.
		var ring := smoothstep(-_islet_far, -_islet_far + ISLET_FADE, s) * (1.0 - smoothstep(-_islet_near - ISLET_FADE, -_islet_near, s))
		var rise := smoothstep(_islet_threshold, _islet_threshold + ISLET_SHOULDER, _islets.get_noise_2d(x, z)) * ring
		if rise > 0.0:
			ground = maxf(ground, lerpf(_seabed, sea_level + _islet_rise, rise))
	return ground


## 0 in lowland, rising to 1 in hilly country: where the hill layers count.
func hilliness(x: float, z: float) -> float:
	return smoothstep(_mask_from, _mask_to, _mask.get_noise_2d(x, z))


## Share of the map's land (the sea floor left out), sampled every `step` metres, where the
## ground rises less than `max_grade` metres per metre.
func walkable_share(step: float, max_grade: float) -> float:
	var b := bounds()
	var good := 0
	var all := 0
	var x := b.position.x
	while x < b.end.x - step:
		var z := b.position.y
		while z < b.end.y - step:
			var lh := land_height(x, z)
			if has_coast() and _is_sea_over(x, z, lh):
				z += step
				continue
			var h := _height_of(x, z, lh)
			var grade := Vector2(height(x + step, z) - h, height(x, z + step) - h).length() / step
			if grade < max_grade:
				good += 1
			all += 1
			z += step
		x += step
	return float(good) / float(all) if all > 0 else 0.0


func _read_coast(coast: Dictionary, seed_value: int) -> void:
	sea_level = float(coast["sea_level"])
	_radius = float(coast["radius"])
	_roundness = maxf(float(coast["roundness"]), 1.0)
	var noise: Dictionary = coast["noise"]
	_coast_noise.seed = seed_value * 7919 + 5501
	_coast_noise.frequency = float(noise["frequency"])
	_coast_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_coast_noise.fractal_octaves = int(noise["octaves"])
	_coast_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_coast_amplitude = float(noise["amplitude"])
	_seabed = sea_level - float(coast["sea_depth"])
	_edge = float(coast["edge"])
	_inland = maxf(float(coast["inland"]), 1.0)
	var beach: Dictionary = coast["beach"]
	_beach_rise = float(beach["rise"])
	_beach_sea = float(beach["sea_band"])
	_beach_land = float(beach["land_band"])
	_sand_grade = float(beach["sand_grade"])
	_sand_height = float(beach["sand_height"])
	_sand_wash = float(beach["wash"])
	var cliff: Dictionary = coast["cliff"]
	_cliff_rise = float(cliff["rise"])
	_cliff_sea = float(cliff["sea_band"])
	_cliff_land = float(cliff["land_band"])
	_cliff_inland = maxf(float(cliff["inland"]), 1.0)
	_reach_in = maxf(maxf(_inland, _cliff_inland), maxf(_beach_land, _cliff_land))
	_cliff_from = float(cliff["from"])
	_cliff_to = float(cliff["to"])
	var islets: Dictionary = coast["islets"]
	_islets.seed = seed_value * 7919 + 8803
	_islets.frequency = float(islets["frequency"])
	_islets.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_islets.fractal_octaves = 1
	_islet_threshold = float(islets["threshold"])
	_islet_near = float(islets["near"])
	_islet_far = float(islets["far"])
	_islet_rise = float(islets["rise"])


## Whether the sea covers (x, z), whose land is `h`: below sea level next to a grid point
## the sea reaches.
func _is_sea_over(x: float, z: float, h: float) -> bool:
	if _sea_of.is_empty() or h >= sea_level:
		return false
	var b := bounds()
	var gx := (x - b.position.x) / _cell
	var gz := (z - b.position.y) / _cell
	if gx < 0.0 or gz < 0.0 or gx > _side - 1 or gz > _side - 1:
		# Past the map's edge it is all sea.
		return true
	for dx in 2:
		for dz in 2:
			var i := clampi(floori(gx) + dx, 0, _side - 1)
			var j := clampi(floori(gz) + dz, 0, _side - 1)
			if _sea_of[j * _side + i] == 1:
				return true
	return false


## Marks the grid points the sea reaches: from every point on the map's edge below sea level,
## on through neighbours below it, but never further in from the coastline than `inland`
## (the land there is floored over the sea, see `_coast_height`): a hollow further in stays
## land or a pond, never a sea behind a strip of beach.
func _find_sea(ground: PackedFloat32Array) -> void:
	_sea_of.resize(_side * _side)
	_sea_of.fill(0)
	var b := bounds()
	var shore := PackedByteArray()
	shore.resize(_side * _side)
	for k in _side * _side:
		shore[k] = 1 if inland(b.position.x + (k % _side) * _cell, b.position.y + (k / _side) * _cell) < _inland else 0
	var stack: Array[int] = []
	for j in _side:
		for i in _side:
			var k := j * _side + i
			if (i == 0 or j == 0 or i == _side - 1 or j == _side - 1) and ground[k] < sea_level:
				_sea_of[k] = 1
				stack.append(k)
	while not stack.is_empty():
		var k: int = stack.pop_back()
		for d: Vector2i in NEIGHBOURS:
			var ni := k % _side + d.x
			var nj := k / _side + d.y
			if ni < 0 or nj < 0 or ni >= _side or nj >= _side:
				continue
			var nk := nj * _side + ni
			if _sea_of[nk] == 0 and ground[nk] < sea_level and shore[nk] == 1:
				_sea_of[nk] = 1
				stack.append(nk)


## The sea floor out past the shore, metres; NAN without a coast.
func seabed() -> float:
	return _seabed if has_coast() else NAN


## The sea's cover on the water survey grid as rectangles, row by row (x, z): every cell with
## the sea at one of its corners or next to it, so a surface over them reaches past every
## shore. Empty without a coast.
func sea_runs() -> Array[Rect2]:
	if _sea_of.is_empty():
		return []
	return _runs(func(k: int) -> bool: return _sea_of[k] == 1)


## Pond `i`'s cover on the water survey grid as rectangles, as `sea_runs`; on an island, none
## over the sea (a pond by the shore stands higher than it).
func pond_runs(i: int) -> Array[Rect2]:
	# Only round the pond's own points: the whole grid once per pond adds up at load.
	var low := Vector2i(_side, _side)
	var high := Vector2i(-1, -1)
	for k in _pond_of.size():
		if _pond_of[k] == i:
			low = Vector2i(mini(low.x, k % _side), mini(low.y, k / _side))
			high = Vector2i(maxi(high.x, k % _side), maxi(high.y, k / _side))
	if high.x < 0:
		return []
	var runs := _runs(func(k: int) -> bool: return _pond_of[k] == i, Rect2i(low - Vector2i(2, 2), high - low + Vector2i(5, 5)))
	if _sea_of.is_empty():
		return runs
	# Cut where a cell has the sea at its middle: the pond's level would float over it.
	var out: Array[Rect2] = []
	for r in runs:
		var start := r.position.x
		var x := r.position.x
		while x < r.end.x:
			var c := Vector2(x + _cell / 2.0, r.position.y + _cell / 2.0)
			if is_sea(c.x, c.y):
				if x > start:
					out.append(Rect2(start, r.position.y, x - start, _cell))
				start = x + _cell
			x += _cell
		if r.end.x > start:
			out.append(Rect2(start, r.position.y, r.end.x - start, _cell))
	return out


## Rectangles, row by row, of every survey cell with a grid point `wet` at one of its corners
## or next to it.
## Only cells inside `within` (grid cells) when it is given.
func _runs(wet: Callable, within := Rect2i()) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var b := bounds()
	var cells := Rect2i(0, 0, _side - 1, _side - 1)
	if within.size != Vector2i.ZERO:
		cells = cells.intersection(within)
	var covered := func(i: int, j: int) -> bool:
		for dj in range(-1, 3):
			for di in range(-1, 3):
				var ni := clampi(i + di, 0, _side - 1)
				var nj := clampi(j + dj, 0, _side - 1)
				if wet.call(nj * _side + ni):
					return true
		return false
	for j in range(cells.position.y, cells.end.y):
		var start := -1
		for i in range(cells.position.x, cells.end.x + 1):
			var on: bool = i < cells.end.x and covered.call(i, j)
			if on and start < 0:
				start = i
			elif not on and start >= 0:
				out.append(Rect2(b.position + Vector2(start, j) * _cell, Vector2(i - start, 1) * _cell))
				start = -1
	return out


## The sea's depth on the water survey grid as an image, one pixel a grid point (metres of
## water, 0 on land), for drawing the sea where no ground is built under it. Null without a
## coast.
func sea_depth_image() -> Image:
	if _sea_of.is_empty():
		return null
	var image := Image.create(_side, _side, false, Image.FORMAT_RF)
	var b := bounds()
	for j in _side:
		for i in _side:
			var depth := 0.0
			if _sea_of[j * _side + i] == 1:
				depth = maxf(sea_level - land_height(b.position.x + i * _cell, b.position.y + j * _cell), 0.0)
			image.set_pixel(i, j, Color(depth, 0.0, 0.0))
	return image


## The rectangle `sea_depth_image` covers, x and z: its pixels' centres are its grid points.
func sea_depth_rect() -> Rect2:
	var b := bounds()
	return Rect2(b.position - Vector2.ONE * _cell / 2.0, Vector2.ONE * _cell * _side)


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


## The land's height at every point of the survey grid (`_cell` apart, `_side` a side).
func _survey() -> PackedFloat32Array:
	var b := bounds()
	var ground := PackedFloat32Array()
	ground.resize(_side * _side)
	for j in _side:
		for i in _side:
			ground[j * _side + i] = land_height(b.position.x + i * _cell, b.position.y + j * _cell)
	return ground


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
	var ground := _survey()
	if has_coast():
		_find_sea(ground)
	var filled := PackedFloat32Array()
	filled.resize(n)
	var seen := PackedByteArray()
	seen.resize(n)
	var heap := MinHeap.new()
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
		# Diagonals too: water spills through a gap between two corners, which the grid's
		# sides alone would miss.
		for d: Vector2i in AROUND:
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
		if label[start] >= 0 or filled[start] - ground[start] < 0.05 or (not _sea_of.is_empty() and _sea_of[start] == 1):
			continue
		# One basin: the cells under water when it is filled to the brim.
		var basin: Array[int] = []
		var stack: Array[int] = [start]
		label[start] = start
		# A hollow that runs into the sea is the sea's, not a pond spilling into it.
		var by_sea := false
		while not stack.is_empty():
			var k: int = stack.pop_back()
			basin.append(k)
			for d: Vector2i in NEIGHBOURS:
				var ni := k % _side + d.x
				var nj := k / _side + d.y
				if ni < 0 or nj < 0 or ni >= _side or nj >= _side:
					continue
				var nk := nj * _side + ni
				if not _sea_of.is_empty() and _sea_of[nk] == 1:
					by_sea = true
					continue
				if label[nk] < 0 and filled[nk] - ground[nk] >= 0.05:
					label[nk] = start
					stack.append(nk)
		if by_sea:
			continue
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


## The dry noise's values that fade from meadow to a full dry patch: a wide band, so the
## patches fade out instead of ending at an edge.
const DRY_FROM := 0.25
const DRY_TO := 0.75
## Metres either side a slope is measured over.
const GRADE_STEP := 2.0
## Metres over which an islet's ring fades in at its edges.
const ISLET_FADE := 40.0
## Metres over which the coastline eases into the open sea kept round the map's edge.
const EDGE_EASE := 120.0
## Metres over which low land near the coast eases onto its floor over the sea.
const FLOOR_EASE := 4.0
## How much faster than the islets the cliff tops' height varies along the coast.
const CLIFF_WOBBLE := 4.0
## How far past its threshold the islet noise rises from the sea to an islet's top.
const ISLET_SHOULDER := 0.2
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const AROUND: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

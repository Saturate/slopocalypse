class_name BloodMarks
extends Node3D
## Blood left on the world: splatter marks where a shot carried on past a body, and pools
## spreading under the dead. Each is a decal lying on the surface. They fade out after
## `mark_seconds` over `fade_seconds`, and at most `max_marks` exist at once; a new one past
## that takes the oldest away (gore.json).

## Render layer (20) for what blood must not paint: people. A pool is a box reaching a little
## above the ground, and a body lying in it or someone walking through it would otherwise turn
## red; a mark on a wall would paint whoever stands against it.
const NO_DECALS := 1 << 19
## Fades a mark out on faces turned away from it, so a splat on a wall doesn't smear down the
## side of a step or a window frame.
const NORMAL_FADE := 0.6
const EDGE_FADE := 0.05
## Texture size in pixels and the size of one blocky cell in it: blood keeps to the game's
## voxel look instead of a smooth blot.
const TEXTURE_SIZE := 64
const CELL := 4
## Fixed seeds: every client draws the same shapes, and nothing is rolled at load beyond them.
const SPLAT_SEED := 385
const POOL_SEED := 386
## Cells vary a little in brightness, so a mark has some texture under its colour.
const SHADE_MIN := 0.85

static var _splat: ImageTexture
static var _pool: ImageTexture

var _decals: Array[Decal] = []
var _ages: Array[float] = []
## Per decal: full size it spreads to, and over how many seconds (0: none, it is full at once).
var _full: Array[Vector3] = []
var _spread: Array[float] = []
var _max := 0
var _seconds := 0.0
var _fade := 0.0
var _depth := 0.0
var _start_share := 0.0
var _pool_seconds := 0.0
var _colour := Color()


func setup(cfg: Dictionary) -> void:
	name = "BloodMarks"
	top_level = true
	_max = int(cfg["max_marks"])
	_seconds = float(cfg["mark_seconds"])
	_fade = float(cfg["fade_seconds"])
	_depth = float(cfg["mark_depth"])
	_start_share = float(cfg["pool_start_share"])
	_pool_seconds = float(cfg["pool_seconds"])
	_colour = BloodEffects.colour(cfg)


## Takes every mark and pool away at once (blood turned off).
func clear() -> void:
	while not _decals.is_empty():
		_remove(0)
	set_process(false)


## A splat at `at` on a surface facing `normal`, `length` metres along `along` (the shot's way
## across the surface) and `width` across it. Null when `max_marks` is 0.
func add_mark(at: Vector3, normal: Vector3, along: Vector3, width: float, length: float) -> Decal:
	return _add(at, normal, along, Vector3(length, _depth, width), 0.0, splat_texture())


## A pool at `at` on ground facing `normal` that spreads to `radius` over `pool_seconds`.
## Null when `max_marks` is 0.
func add_pool(at: Vector3, normal: Vector3, radius: float) -> Decal:
	var along := normal.cross(Vector3.RIGHT if absf(normal.x) < 0.9 else Vector3.FORWARD)
	# Turned at random, so pools side by side don't look stamped from one shape.
	along = along.rotated(normal.normalized(), randf() * TAU)
	return _add(at, normal, along, Vector3(radius * 2.0, _depth, radius * 2.0), _pool_seconds, pool_texture())


func count() -> int:
	return _decals.size()


## The mark or pool added last, or null.
func newest() -> Decal:
	return _decals.back() if not _decals.is_empty() else null


func _process(delta: float) -> void:
	var prof := Prof.start()
	advance(delta)
	Prof.stop(&"gore/marks", prof)


## Ages every mark by `delta` seconds: pools spread, old marks fade and go.
func advance(delta: float) -> void:
	var i := 0
	while i < _decals.size():
		_ages[i] += delta
		var age := _ages[i]
		if age >= _seconds + _fade:
			_remove(i)
			continue
		var decal := _decals[i]
		if _spread[i] > 0.0:
			var t := clampf(age / _spread[i], 0.0, 1.0)
			decal.size = _spread_size(_full[i], t)
		if age > _seconds:
			decal.modulate.a = _colour.a * (1.0 - (age - _seconds) / _fade)
		i += 1
	set_process(not _decals.is_empty())


func _add(at: Vector3, normal: Vector3, along: Vector3, full: Vector3, spread: float, texture: Texture2D) -> Decal:
	if _max <= 0:
		return null
	while _decals.size() >= _max:
		_remove(0)
	var y := normal.normalized()
	var x := (along - y * along.dot(y)).normalized()
	if x.length() < 0.5:
		x = y.cross(Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD).normalized()
	var decal := Decal.new()
	decal.texture_albedo = texture
	decal.modulate = _colour
	decal.normal_fade = NORMAL_FADE
	# The default fade towards the box's top and bottom thins a mark on anything not dead
	# centre in it; road paint and kerbs sit a few centimetres off and showed through.
	decal.upper_fade = EDGE_FADE
	decal.lower_fade = EDGE_FADE
	decal.cull_mask = 0xFFFFF & ~NO_DECALS
	decal.size = full if spread <= 0.0 else _spread_size(full, 0.0)
	add_child(decal)
	decal.global_transform = Transform3D(Basis(x, y, x.cross(y)), at)
	_decals.append(decal)
	_ages.append(0.0)
	_full.append(full)
	_spread.append(spread)
	set_process(true)
	return decal


## Spreads fast at first and slows as it reaches full size, like a pool running out of blood.
func _spread_size(full: Vector3, t: float) -> Vector3:
	var share := lerpf(_start_share, 1.0, 1.0 - (1.0 - t) * (1.0 - t))
	return Vector3(full.x * share, full.y, full.z * share)


func _remove(i: int) -> void:
	var decal := _decals[i]
	_decals.remove_at(i)
	_ages.remove_at(i)
	_full.remove_at(i)
	_spread.remove_at(i)
	if is_instance_valid(decal):
		decal.queue_free()
		remove_child(decal)


## A splash: a ragged blob of cells with a few drops flung around it. White with alpha; the
## decal's modulate colours it.
static func splat_texture() -> ImageTexture:
	if _splat == null:
		_splat = _cells(SPLAT_SEED, 0.28, 0.12, 6)
	return _splat


## A pool: a rounder, fuller blob with a few drops at its edge.
static func pool_texture() -> ImageTexture:
	if _pool == null:
		_pool = _cells(POOL_SEED, 0.4, 0.1, 3)
	return _pool


## Cells inside a circle of `radius` (share of the texture) whose edge wobbles by `ragged`,
## plus `drops` single cells scattered outside it.
static func _cells(seed_value: int, radius: float, ragged: float, drops: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var image := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0))
	var cells := TEXTURE_SIZE / CELL
	var centre := Vector2(cells, cells) * 0.5
	# The edge's wobble as a few bumps around the circle, so neighbouring cells agree.
	var bumps: Array[float] = []
	for i in 8:
		bumps.append(rng.randf_range(-ragged, ragged))
	for cy in cells:
		for cx in cells:
			var offset := Vector2(cx + 0.5, cy + 0.5) - centre
			var angle := fposmod(offset.angle(), TAU) / TAU * bumps.size()
			var a := int(angle) % bumps.size()
			var edge := (radius + lerpf(bumps[a], bumps[(a + 1) % bumps.size()], angle - floorf(angle))) * cells
			if offset.length() <= edge:
				_fill_cell(image, cx, cy, rng.randf_range(SHADE_MIN, 1.0))
	for i in drops:
		var angle := rng.randf_range(0.0, TAU)
		var at := centre + Vector2.from_angle(angle) * rng.randf_range(radius + 0.06, 0.48) * cells
		_fill_cell(image, clampi(int(at.x), 0, cells - 1), clampi(int(at.y), 0, cells - 1), 1.0)
	return ImageTexture.create_from_image(image)


static func _fill_cell(image: Image, cx: int, cy: int, alpha: float) -> void:
	image.fill_rect(Rect2i(cx * CELL, cy * CELL, CELL, CELL), Color(alpha, alpha, alpha, 1.0))

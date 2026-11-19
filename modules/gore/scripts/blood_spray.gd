class_name BloodSpray
extends MultiMeshInstance3D
## Small dark-red cubes thrown out of a body a bullet went into. One ring of `max_drops`
## drops (gore.json) drawn as one multimesh with one material made when the module loads, so
## blood never builds a mesh or a shader mid-fight. A new drop takes the next slot in the
## ring, which is the oldest one once the ring is full. All slots are written to the
## multimesh in one buffer each frame; empty ones are drawn at zero size.

## Upward speed on top of the shot's, as a share of the drop's speed: drops arc before they
## fall instead of dropping straight out of the wound.
const LIFT := 0.3
## Drops vary in size around `drop_size` so a spray doesn't read as a grid of equal cubes.
const SCALE_MIN := 0.6
const SCALE_MAX := 1.4
## Floats per drop in the multimesh buffer: a 3x4 transform, row by row.
const STRIDE := 12
## The warm-up drop's scale: drawn, but far too small to see.
const WARM_SCALE := 0.001
## Age of an empty slot. Not the lifetime itself: ages are stored as 32-bit floats and would
## never compare equal to it.
const EMPTY := -1.0

var _positions := PackedVector3Array()
var _velocities := PackedVector3Array()
## Seconds each slot's drop has flown; EMPTY for a slot with no drop.
var _ages := PackedFloat32Array()
var _bases: Array[Basis] = []
var _buffer := PackedFloat32Array()
var _next := 0
var _live := 0
var _capacity := 0
var _lifetime := 0.0
var _speed := 0.0
var _speed_jitter := 0.0
var _angle_jitter := 0.0
var _size := 0.0
var _rng := RandomNumberGenerator.new()
var _gravity := Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


func setup(cfg: Dictionary) -> void:
	_capacity = maxi(int(cfg["max_drops"]), 0)
	_lifetime = float(cfg["drop_seconds"])
	_speed = float(cfg["spray_speed"])
	_speed_jitter = float(cfg["spray_speed_jitter"])
	_angle_jitter = float(cfg["spray_angle_jitter_degrees"])
	_size = float(cfg["drop_size"])
	if _lifetime <= 0.0:
		# A drop that lives no time is no drop; it would also divide by zero as it shrinks.
		_capacity = 0
	_rng.randomize()
	_positions.resize(_capacity)
	_velocities.resize(_capacity)
	_ages.resize(_capacity)
	_ages.fill(EMPTY)
	_bases.resize(_capacity)
	_bases.fill(Basis.IDENTITY)
	_buffer.resize(_capacity * STRIDE)
	name = "BloodSpray"
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box := BoxMesh.new()
	box.size = Vector3.ONE * _size
	box.material = BloodEffects.material(cfg)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = _capacity
	mm.visible_instance_count = 0
	multimesh = mm


## Throws `count` drops from `at` along `direction`.
func spray(at: Vector3, direction: Vector3, count: int) -> void:
	if _capacity <= 0:
		return
	for i in count:
		var slot := _next
		_next = (_next + 1) % _capacity
		if _ages[slot] < 0.0:
			_live += 1
		_positions[slot] = at
		_velocities[slot] = VoxelDebris.launch_velocity(direction, _speed, _speed_jitter, _angle_jitter, _rng) + Vector3.UP * _speed * LIFT
		_ages[slot] = 0.0
		_bases[slot] = Basis.from_euler(Vector3(_rng.randf_range(0.0, TAU), _rng.randf_range(0.0, TAU), 0.0)).scaled(Vector3.ONE * _rng.randf_range(SCALE_MIN, SCALE_MAX))
	_place()
	set_process(_live > 0)


## One drop too small to see at `at`, so the spray's draw is set up while loading.
func warm(at: Vector3) -> void:
	if _capacity <= 0:
		return
	spray(at, Vector3.DOWN, 1)
	_bases[(_next - 1 + _capacity) % _capacity] = Basis.from_scale(Vector3.ONE * WARM_SCALE)
	_place()


## Drops every drop in flight (blood turned off).
func clear() -> void:
	_ages.fill(EMPTY)
	_live = 0
	_place()
	set_process(false)


func live_count() -> int:
	return _live


## Where the drops in flight are, and how fast they go, in no particular order.
func live_positions() -> PackedVector3Array:
	return _live_values(_positions)


func live_velocities() -> PackedVector3Array:
	return _live_values(_velocities)


func _live_values(values: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in _capacity:
		if _ages[i] >= 0.0:
			out.append(values[i])
	return out


func _process(delta: float) -> void:
	var prof := Prof.start()
	advance(delta)
	Prof.stop(&"gore/spray", prof)


## Moves the drops on by `delta` seconds and lets go of those past their time.
func advance(delta: float) -> void:
	for i in _capacity:
		if _ages[i] < 0.0:
			continue
		_ages[i] += delta
		if _ages[i] >= _lifetime:
			_ages[i] = EMPTY
			_live -= 1
			continue
		_velocities[i] += _gravity * delta
		_positions[i] += _velocities[i] * delta
	_place()
	if _live <= 0:
		set_process(false)


func _place() -> void:
	if multimesh == null:
		return
	multimesh.visible_instance_count = _capacity if _live > 0 else 0
	if _live <= 0:
		return
	var low := Vector3.INF
	var high := -Vector3.INF
	for i in _capacity:
		var o := i * STRIDE
		if _ages[i] < 0.0:
			for k in STRIDE:
				_buffer[o + k] = 0.0
			continue
		# Drops shrink away over their life instead of popping out.
		var s := 1.0 - _ages[i] / _lifetime
		var b := _bases[i]
		var p := _positions[i]
		_buffer[o] = b.x.x * s
		_buffer[o + 1] = b.y.x * s
		_buffer[o + 2] = b.z.x * s
		_buffer[o + 3] = p.x
		_buffer[o + 4] = b.x.y * s
		_buffer[o + 5] = b.y.y * s
		_buffer[o + 6] = b.z.y * s
		_buffer[o + 7] = p.y
		_buffer[o + 8] = b.x.z * s
		_buffer[o + 9] = b.y.z * s
		_buffer[o + 10] = b.z.z * s
		_buffer[o + 11] = p.z
		low = low.min(p)
		high = high.max(p)
	multimesh.buffer = _buffer
	# The drops are placed in world space on a node at the origin; bounds that follow them keep
	# the spray from being culled, or drawn when it is out of view.
	custom_aabb = AABB(low - Vector3.ONE * _size, high - low + Vector3.ONE * _size * 2.0)

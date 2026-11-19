class_name BloodSpray
extends MultiMeshInstance3D
## Small dark-red cubes thrown out of a body a bullet went into. One pool of `max_drops`
## drops (gore.json) drawn as one multimesh with one material made when the module loads, so
## blood never builds a mesh or a shader mid-fight. Live drops are kept packed at the front;
## when the pool is full, a new drop takes the place of the oldest.

## Upward speed on top of the shot's, as a share of the drop's speed: drops arc before they
## fall instead of dropping straight out of the wound.
const LIFT := 0.3
## Drops vary in size around `drop_size` so a spray doesn't read as a grid of equal cubes.
const SCALE_MIN := 0.6
const SCALE_MAX := 1.4

var _positions: Array[Vector3] = []
var _velocities: Array[Vector3] = []
var _ages: Array[float] = []
var _bases: Array[Basis] = []
var _capacity := 0
var _lifetime := 0.0
var _speed := 0.0
var _speed_jitter := 0.0
var _angle_jitter := 0.0
var _size := 0.0
var _rng := RandomNumberGenerator.new()
var _gravity := Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


func setup(cfg: Dictionary) -> void:
	_capacity = int(cfg["max_drops"])
	_lifetime = float(cfg["drop_seconds"])
	_speed = float(cfg["spray_speed"])
	_speed_jitter = float(cfg["spray_speed_jitter"])
	_angle_jitter = float(cfg["spray_angle_jitter_degrees"])
	_size = float(cfg["drop_size"])
	_rng.randomize()
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
	for i in count:
		var v := VoxelDebris.launch_velocity(direction, _speed, _speed_jitter, _angle_jitter, _rng) + Vector3.UP * _speed * LIFT
		var basis := Basis.from_euler(Vector3(_rng.randf_range(0.0, TAU), _rng.randf_range(0.0, TAU), 0.0)).scaled(Vector3.ONE * _rng.randf_range(SCALE_MIN, SCALE_MAX))
		if _positions.size() < _capacity:
			_positions.append(at)
			_velocities.append(v)
			_ages.append(0.0)
			_bases.append(basis)
		else:
			var oldest := _oldest()
			_positions[oldest] = at
			_velocities[oldest] = v
			_ages[oldest] = 0.0
			_bases[oldest] = basis
	_place()
	set_process(not _positions.is_empty())


## One drop too small to see at `at`, so the spray's draw is set up while loading.
func warm(at: Vector3) -> void:
	spray(at, Vector3.DOWN, 1)
	_bases[_bases.size() - 1] = Basis.from_scale(Vector3.ONE * BloodMarks.KEEPER_SIZE)
	_place()


func live_count() -> int:
	return _positions.size()


func drop_position(i: int) -> Vector3:
	return _positions[i]


func drop_velocity(i: int) -> Vector3:
	return _velocities[i]


func _process(delta: float) -> void:
	var prof := Prof.start()
	advance(delta)
	Prof.stop(&"gore/spray", prof)


## Moves the drops on by `delta` seconds and lets go of those past their time.
func advance(delta: float) -> void:
	var i := 0
	while i < _positions.size():
		_ages[i] += delta
		if _ages[i] >= _lifetime:
			_remove(i)
			continue
		_velocities[i] += _gravity * delta
		_positions[i] += _velocities[i] * delta
		i += 1
	_place()
	if _positions.is_empty():
		set_process(false)


func _oldest() -> int:
	var best := 0
	for i in _ages.size():
		if _ages[i] > _ages[best]:
			best = i
	return best


## Swaps the last live drop into slot `i`, so the live ones stay at the front.
func _remove(i: int) -> void:
	var last := _positions.size() - 1
	_positions[i] = _positions[last]
	_velocities[i] = _velocities[last]
	_ages[i] = _ages[last]
	_bases[i] = _bases[last]
	_positions.remove_at(last)
	_velocities.remove_at(last)
	_ages.remove_at(last)
	_bases.remove_at(last)


func _place() -> void:
	if multimesh == null:
		return
	var n := _positions.size()
	multimesh.visible_instance_count = n
	if n == 0:
		return
	var low := _positions[0]
	var high := _positions[0]
	for i in n:
		# Drops shrink away over their life instead of popping out.
		var shrink := 1.0 - _ages[i] / _lifetime
		multimesh.set_instance_transform(i, Transform3D(_bases[i].scaled(Vector3.ONE * shrink), _positions[i]))
		low = low.min(_positions[i])
		high = high.max(_positions[i])
	# The drops are placed in world space on a node at the origin; bounds that follow them keep
	# the spray from being culled, or drawn when it is out of view.
	custom_aabb = AABB(low - Vector3.ONE * _size, high - low + Vector3.ONE * _size * 2.0)

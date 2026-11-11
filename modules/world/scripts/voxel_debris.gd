class_name VoxelDebris
extends MultiMeshInstance3D
## Little voxel cubes thrown out of whatever breaks (bark off a trunk, dirt from a crater,
## asphalt from the road, planks from a building). Client-only and purely for show, so the
## randomness needs no sync: every burst rolls its own speeds, directions and spins. Each
## source's numbers come from `debris.json` (`sources.<source>`). The burst moves its own
## cubes and frees itself when their lifetime is up.

const CONFIG := "res://modules/world/data/debris.json"
const REQUIRED := {
	"count": TYPE_FLOAT,
	"speed": TYPE_FLOAT,
	"speed_jitter": TYPE_FLOAT,
	"angle_jitter_degrees": TYPE_FLOAT,
	"spin_max": TYPE_FLOAT,
	"lifetime_seconds": TYPE_FLOAT,
}
## Cube edge in metres, and how much single cubes vary in size around it.
const CUBE := 0.12
const SCALE_MIN := 0.6
const SCALE_MAX := 1.4

static var _sources: Dictionary = {}

## Per cube: launch velocity (metres per second) and spin (radians per second about each axis).
var velocities: Array[Vector3] = []
var spins: Array[Vector3] = []
var lifetime := 0.0

var _positions: Array[Vector3] = []
var _moving: Array[Vector3] = []
var _bases: Array[Basis] = []
var _scales: Array[float] = []
var _age := 0.0
var _gravity := Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


## The config entry for `source` (`building`, `crater`, `tree`, ...), or an empty dictionary
## after logging why.
static func config(source: StringName) -> Dictionary:
	if _sources.is_empty():
		var data: Variant = Data.load_json(CONFIG)
		if not data is Dictionary or not (data as Dictionary).get("sources") is Dictionary:
			Log.error(&"debris", "%s: needs a `sources` object" % CONFIG)
			return {}
		_sources = data["sources"]
	var entry: Variant = _sources.get(String(source))
	if not entry is Dictionary or not Data.require("%s sources.%s" % [CONFIG, source], entry, REQUIRED):
		Log.error(&"debris", "%s: no usable entry for `%s`" % [CONFIG, source])
		return {}
	return entry


## A burst of `source`'s debris in `colour` from `at`, thrown along `towards`. `count` and
## `speed` replace the entry's (craters scale them with the hole's size).
static func burst(parent: Node, at: Vector3, towards: Vector3, colour: Color, source: StringName, count := -1, speed := -1.0, rng: RandomNumberGenerator = null) -> VoxelDebris:
	if not parent.is_inside_tree():
		return null
	var cfg := config(source)
	if cfg.is_empty():
		return null
	var n := count if count >= 0 else int(cfg["count"])
	if n <= 0:
		return null
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var debris := VoxelDebris.new()
	debris.setup(towards, colour, cfg, n, speed if speed >= 0.0 else float(cfg["speed"]), rng)
	debris.top_level = true
	parent.add_child(debris)
	debris.global_position = at
	return debris


## One cube's launch velocity: `speed` scaled by up to +/- `speed_jitter`, along `base`
## tilted by up to `angle_jitter_degrees` towards a random side.
static func launch_velocity(base: Vector3, speed: float, speed_jitter: float, angle_jitter_degrees: float, rng: RandomNumberGenerator) -> Vector3:
	var dir := base.normalized() if base.length() > 0.01 else Vector3.UP
	var tilt := deg_to_rad(rng.randf_range(0.0, angle_jitter_degrees))
	if tilt > 0.0:
		var side := dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.FORWARD).normalized()
		side = side.rotated(dir, rng.randf_range(0.0, TAU))
		dir = dir.rotated(side, tilt)
	return dir * speed * (1.0 + rng.randf_range(-speed_jitter, speed_jitter))


static func spin(spin_max: float, rng: RandomNumberGenerator) -> Vector3:
	return Vector3(rng.randf_range(-spin_max, spin_max), rng.randf_range(-spin_max, spin_max), rng.randf_range(-spin_max, spin_max))


func setup(towards: Vector3, colour: Color, cfg: Dictionary, count: int, speed: float, rng: RandomNumberGenerator) -> void:
	lifetime = float(cfg["lifetime_seconds"])
	for i in count:
		velocities.append(launch_velocity(towards, speed, float(cfg["speed_jitter"]), float(cfg["angle_jitter_degrees"]), rng))
		spins.append(spin(float(cfg["spin_max"]), rng))
		_positions.append(Vector3.ZERO)
		_moving.append(velocities[i])
		_bases.append(Basis.from_euler(Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), 0.0)))
		_scales.append(rng.randf_range(SCALE_MIN, SCALE_MAX))
	var box := BoxMesh.new()
	box.size = Vector3.ONE * CUBE
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	box.material = material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = count
	multimesh = mm
	# The cubes move every frame; one box covering everywhere they can reach saves
	# recomputing bounds.
	var reach := speed * (1.0 + float(cfg["speed_jitter"])) * lifetime + 0.5 * _gravity.length() * lifetime * lifetime
	custom_aabb = AABB(-Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
	_place()


func _process(delta: float) -> void:
	var t := Prof.start()
	_age += delta
	if _age >= lifetime:
		queue_free()
		Prof.stop(&"world/debris", t)
		return
	for i in _moving.size():
		_moving[i] += _gravity * delta
		_positions[i] += _moving[i] * delta
		var w := spins[i]
		if w.length() > 0.0:
			_bases[i] = Basis(w.normalized(), w.length() * delta) * _bases[i]
	_place()
	Prof.stop(&"world/debris", t)


func _place() -> void:
	for i in _positions.size():
		multimesh.set_instance_transform(i, Transform3D(_bases[i].orthonormalized().scaled(Vector3.ONE * _scales[i]), _positions[i]))

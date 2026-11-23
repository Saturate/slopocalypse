extends Node
## Capture setup: the apartment block in the asset library, one variant every 40 frames, each
## seen from a fixed angle (yaw PI looks at the street side, 0 at the courtyard side).

const LIBRARY := "res://modules/voxkit/library/asset_library.gd"
const STEP := 40

## [values, yaw, pitch, zoom] per shot; zoom scales the library's own framing distance.
var shots: Array[Array] = [
	[{}, PI - 0.55, -0.22, 0.55],
	[{}, 0.6, -0.3, 0.55],
	[{"walls": 1.0, "roof": 1.0, "balconies": 2.0, "railing": 1.0, "floors": 6.0, "stairwells": 3.0, "elevators": 2.0}, 0.45, -0.25, 0.55],
	[{"walls": 2.0, "roof": 2.0, "railing": 2.0, "balcony_sides": 1.0, "floors": 8.0, "seed": 5.0}, PI - 0.5, -0.2, 0.55],
	[{"floors": 2.0, "stairwells": 1.0, "basement": 0.0, "balconies": 3.0, "elevators": 0.0, "roof_windows": 2.0}, 0.7, -0.35, 0.6],
	[{"walls": 1.0, "floors": 5.0, "windows": 3.0, "seed": 9.0}, PI - 0.9, -0.12, 0.55],
]

var _library: AssetLibrary
var _camera: OrbitCamera
var _ticks := 0


func _ready() -> void:
	_library = (load(LIBRARY) as GDScript).new()
	add_child(_library)


func _process(_delta: float) -> void:
	_ticks += 1
	if _ticks % STEP != 1:
		return
	var shot := shots[mini(_ticks / STEP, shots.size() - 1)]
	var index := VoxCatalog.all().map(func(g: VoxGenerator) -> String: return g.title()).find(VoxApartment.new().title())
	_library.select(index)
	var values: Dictionary = shot[0]
	for key: String in values:
		_library.set_value(key, values[key])
	_library.rebuild_now()
	if _camera == null:
		_camera = _find_camera(_library)
	_camera.turntable = false
	_camera.yaw = shot[1]
	_camera.pitch = shot[2]
	_camera.distance *= float(shot[3])


func _find_camera(node: Node) -> OrbitCamera:
	for child in node.get_children():
		if child is OrbitCamera:
			return child
		var found := _find_camera(child)
		if found != null:
			return found
	return null

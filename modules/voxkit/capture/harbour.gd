extends Node
## Capture setup: the harbour and store pieces (#575) in the asset library, each from one or
## two angles: jetty, boat sheds, the boat, the BLÅGUL warehouse front and back, shelving,
## flat packs and every harbour prop. One view every 30 frames; `--frames 540 --sheet 18`.

const LIBRARY := "res://modules/voxkit/library/asset_library.gd"
const STEP := 30

var _library: AssetLibrary
var _ticks := 0
## Each [generator title, values, yaw, pitch, zoom (share of the library's framing distance)].
var _views: Array[Array] = [
	["Jetty", {}, 0.7, -0.35],
	["Jetty", {"sections": 8.0}, 2.4, -0.25, 0.6],
	["Boat shed", {}, 0.5, -0.3],
	["Boat shed", {}, 2.6, -0.3],
	["Boat shed", {"paint": 0.0, "doors": 1.0}, 0.6, -0.25],
	["Boat", {}, 0.9, -0.45],
	["Boat", {}, 3.6, -0.3],
	["Boat", {"paint": 0.0}, 1.7, -0.8],
	["BLÅGUL warehouse", {}, 0.4, -0.3, 0.55],
	["BLÅGUL warehouse", {}, 2.7, -0.35, 0.55],
	["BLÅGUL warehouse", {}, -0.6, -0.9, 0.6],
	["Shelving", {}, 0.5, -0.3],
	["Flat-pack boxes", {}, 0.7, -0.5],
	["Harbour prop", {"kind": 0.0}, 0.7, -0.4],
	["Harbour prop", {"kind": 1.0, "colour": 2.0}, 0.7, -0.5],
	["Harbour prop", {"kind": 2.0, "colour": 1.0}, 0.7, -0.3],
	["Harbour prop", {"kind": 3.0}, 0.7, -0.35],
	["Harbour prop", {"kind": 0.0, "colour": 2.0, "count": 5.0}, 2.2, -0.3],
]


func _ready() -> void:
	_library = (load(LIBRARY) as GDScript).new()
	add_child(_library)


func _process(_delta: float) -> void:
	_ticks += 1
	if _ticks % STEP == 4:
		_zoom()
	if _ticks % STEP != 1:
		return
	var view := _ticks / STEP
	if view >= _views.size():
		return
	var spec: Array = _views[view]
	var titles := VoxCatalog.all().map(func(g: VoxGenerator) -> String: return g.title())
	_library.select(titles.find(spec[0]))
	var values: Dictionary = spec[1]
	for key: String in values:
		_library.set_value(key, values[key])
	var camera := _library.find_children("*", "OrbitCamera", true, false)[0] as OrbitCamera
	camera.turntable = false
	camera.yaw = spec[2]
	camera.pitch = spec[3]


## Pulls the camera in after the library has framed the model (a few frames after picking it).
func _zoom() -> void:
	var view := _ticks / STEP
	if view >= _views.size():
		return
	var spec: Array = _views[view]
	if spec.size() < 5:
		return
	var camera := _library.find_children("*", "OrbitCamera", true, false)[0] as OrbitCamera
	camera.distance *= float(spec[4])

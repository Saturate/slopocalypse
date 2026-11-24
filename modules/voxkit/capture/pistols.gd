extends Node
## Capture setup: the asset library on each new pistol in turn (Five-seveN, Desert Eagle,
## Python), whole and then each of its parts. One view every 30 frames.

const LIBRARY := "res://modules/voxkit/library/asset_library.gd"
const STEP := 30

var _library: AssetLibrary
var _ticks := 0
var _views: Array[Array] = []


func _ready() -> void:
	_library = (load(LIBRARY) as GDScript).new()
	add_child(_library)
	var titles := VoxCatalog.all().map(func(g: VoxGenerator) -> String: return g.title())
	for gen: VoxHandgun in [VoxFiveSeven.new(), VoxDesertEagle.new(), VoxPython.new()]:
		for part in gen.parts().size():
			_views.append([titles.find(gen.title()), part])


func _process(_delta: float) -> void:
	_ticks += 1
	if _ticks % STEP != 1:
		return
	var view := _ticks / STEP
	if view >= _views.size():
		return
	_library.select(int(_views[view][0]))
	_library.set_value("part", float(_views[view][1]))

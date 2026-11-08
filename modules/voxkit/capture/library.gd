extends Node
## Capture setup: the asset library going through every asset with the pixel filter on, then
## the roadside scene with it off and on. One asset every 40 frames.

const LIBRARY := "res://modules/voxkit/library/asset_library.gd"
const STEP := 40

var _library: AssetLibrary
var _ticks := 0


func _ready() -> void:
	_library = (load(LIBRARY) as GDScript).new()
	add_child(_library)


func _process(_delta: float) -> void:
	_ticks += 1
	if _ticks % STEP != 1:
		return
	var step := _ticks / STEP
	var count := VoxCatalog.all().size()
	if step <= count:
		_library.select(step)
	elif step == count + 1:
		_library.set_pixel_filter(false)
	else:
		_library.set_pixel_filter(true)

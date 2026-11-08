extends Node
## Capture setup: a short, heavily worn road in the asset library: patches and tears under the
## lines, chipped paint, nothing spilling onto the shoulders.

const LIBRARY := "res://modules/voxkit/library/asset_library.gd"

var _library: AssetLibrary


func _ready() -> void:
	_library = (load(LIBRARY) as GDScript).new()
	add_child(_library)
	_library.select(0)
	_library.set_value("length", 14.0)
	_library.set_value("wear", 0.9)
	_library.set_value("potholes", 5.0)
	_library.set_value("tear_size", 2.0)

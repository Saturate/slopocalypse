extends Node
## Capture setup: the asset library on the bolt-action rifle, whole and then each part in
## turn (receiver, barrel, stock, bolt, magazine, scope). One view every 40 frames.

const LIBRARY := "res://modules/voxkit/library/asset_library.gd"
const STEP := 40

var _library: AssetLibrary
var _ticks := 0


func _ready() -> void:
	_library = (load(LIBRARY) as GDScript).new()
	add_child(_library)
	var titles := VoxCatalog.all().map(func(g: VoxGenerator) -> String: return g.title())
	_library.select(titles.find(VoxBoltRifle.new().title()))


func _process(_delta: float) -> void:
	_ticks += 1
	if _ticks % STEP != 1:
		return
	var part := _ticks / STEP
	if part > 0 and part < VoxBoltRifle.PARTS.size():
		_library.set_value("part", float(part))

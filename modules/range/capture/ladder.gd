extends Node3D
## Capture setup: one subject of the impact ladder (`ImpactLadder`) on the flat test world,
## as a row of fresh copies, one per hit, each labelled with what hit it. All are hit at
## once; then the camera visits each copy in turn, smallest hit first, so a 9-panel sheet
## reads rounds, small blasts, big blasts down its rows.
##
##   LADDER_SUBJECT="House, brick" node tools/capture.ts --setup res://modules/range/capture/ladder.gd --out screenshots/ladder.png --frames 180 --sheet 9
##
## `LADDER_SUBJECT` is a subject's label (see `ImpactLadder.subjects`); the first one when unset.
## `--frames` is `DWELL` times the number of hits.

const WORLD := "res://modules/world/scenes/flat_world.tscn"
const MISSIONS := "res://modules/missions/missions_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
## Frames per panel; the first panel is grabbed this long after the hits.
const DWELL := 20
## Copies stand this much further apart than they are wide, so the biggest blast on one
## doesn't reach the next.
const GAP := 10.0
const OFFSET := 60.0

var _missions: Node
var _cam: Camera3D
var _subject: Dictionary = {}
var _hits: Array[Dictionary] = []
var _frame := 0


func _ready() -> void:
	add_child((load(WORLD) as PackedScene).instantiate())
	add_child((load(INVENTORY) as GDScript).new())
	_missions = (load(MISSIONS) as GDScript).new()
	add_child(_missions)
	EventBus.publish(&"world.ready", {"spawn": Vector3.ZERO})
	var subjects := ImpactLadder.subjects()
	var wanted := OS.get_environment("LADDER_SUBJECT")
	_subject = subjects[0]
	for s in subjects:
		if str(s.get("label", "")) == wanted:
			_subject = s
	_hits = ImpactLadder.hits()
	var entries: Array = []
	for h in _hits.size():
		entries.append(ImpactLadder.entry(_subject, 0, _copy_at(h)))
	_missions.set(&"buildings", entries)
	_missions.call(&"_build_buildings")
	var nodes: Array[MissionBuilding] = _missions.call(&"building_nodes")
	for i in nodes.size():
		var label := Label3D.new()
		label.text = "%s: %s" % [_subject.get("label", ""), _hits[i]["label"]]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 48
		label.pixel_size = 0.005
		label.outline_size = 12
		label.position = Vector3(0.0, float(nodes[i].spec["wall_height"]) + 1.4, 0.0)
		nodes[i].add_child(label)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	add_child(_cam)
	_cam.current = true


## Copy `h`'s place: along +X, clear of the flat world's spawn and car spot.
func _copy_at(h: int) -> Vector3:
	return Vector3(OFFSET + h * (float(_subject.get("width", 5.0)) + GAP), 0.0, OFFSET)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 1:
		var nodes: Array[MissionBuilding] = _missions.call(&"building_nodes")
		for i in nodes.size():
			ImpactLadder.apply(nodes[i], _hits[i])
	if (_frame - 1) % DWELL == 0:
		_frame_copy(mini((_frame - 1) / DWELL, _hits.size() - 1))


## Points the camera at copy `h`'s front from a little to one side, close enough to see holes,
## far enough to see the rubble round it.
func _frame_copy(h: int) -> void:
	var w := float(_subject.get("width", 5.0))
	var d := float(_subject.get("depth", 4.0))
	var target := _copy_at(h) + Vector3(0.0, 1.4, -d / 2.0)
	var back := w * 1.15 + 1.5
	_cam.global_position = target + Vector3(back * 0.3, back * 0.35, -back)
	_cam.look_at(target, Vector3.UP)

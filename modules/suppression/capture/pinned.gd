extends Node3D
## Capture setup: the enemies module's `suppress` scene (first person beside a chest-high wall,
## a squad with a gunner 20 m ahead; the player steps behind the wall and the gunner keeps
## firing at it) with this module on: the screen edges darken as rounds pass close, the view
## shakes a little on each, and once the squad is taken away (STOP_TICK) the darkening wears
## off. Run it with --frames 450.

const SCENE := "res://modules/enemies/capture/suppress.gd"
const MODULE := "res://modules/suppression/suppression_module.gd"
## Physics ticks (two to each captured frame) before the squad is removed, so the fire stops.
const STOP_TICK := 560

var _module: Node
var _ticks := 0


func _ready() -> void:
	# First, so it hears the player spawn the scene announces.
	_module = (load(MODULE) as GDScript).new()
	_module.name = "Suppression"
	add_child(_module)
	var scene: Node3D = (load(SCENE) as GDScript).new()
	add_child(scene)


func _physics_process(_delta: float) -> void:
	_ticks += 1
	if _ticks % 30 == 0:
		Log.info(&"capture", "tick %d suppression %.2f" % [_ticks, float(_module.call(&"local_level"))])
	if _ticks == STOP_TICK:
		for soldier: Node in get_tree().get_nodes_in_group(&"enemies"):
			soldier.queue_free()

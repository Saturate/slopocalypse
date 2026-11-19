extends Node3D
## Capture setup: the "Report a bug" form open over the world, with a description typed in,
## then saved (into a temp folder) so it shows where the file went.

const WORLD := "res://modules/world/scenes/world.tscn"
const MODULE := "res://modules/report/report_module.gd"

var _module: Node
var _ticks := 0


func _ready() -> void:
	await VoxelWorld.add_and_wait(self, WORLD)
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = Vector3(0.0, 2.0, 6.0)
	camera.look_at(Vector3(0.0, 1.0, 0.0))
	camera.current = true
	_module = (load(MODULE) as GDScript).new()
	_module.set(&"folder", OS.get_cache_dir().path_join("slopocalypse-capture-reports"))
	add_child(_module)
	_module.call(&"open")
	var note := _module.get_node("ReportScreen").find_child("Note", true, false) as TextEdit
	note.text = "Big hitch when the soldier in the small house died. Happened twice."
	# A focused box takes whatever keys the desktop sends the capture window.
	note.release_focus()


func _physics_process(_delta: float) -> void:
	if _module == null:
		return
	_ticks += 1
	# The sheet's frames fall at about 2.5 s and 5 s: before and after saving.
	if _ticks == 220:
		var screen := _module.get_node("ReportScreen") as ReportScreen
		var shot := PackedByteArray()
		# Saves the way the button does, without opening a file manager window.
		var path: String = _module.call(&"save_report", "bug", "capture", shot)
		screen.set(&"_saved_path", path)
		(screen.find_child("Status", true, false) as Label).text = ReportScreen.saved_text(path)
		(screen.find_child("Save", true, false) as Button).visible = false
		(screen.find_child("Show", true, false) as Button).visible = true

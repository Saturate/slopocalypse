extends Node
## Main scene root. A player who launched without a mode gets the main menu first; then the
## session starts and every enabled module loads as a child of `Modules`. Leaving a session
## reloads this scene, which frees the modules and brings the menu back.

const MODULES_ROOT := "res://modules"
## The voxel kit's asset library, if that module is there and on.
const LIBRARY := "res://modules/voxkit/library/asset_library.gd"

## The test range module (a solo game on a row of buildings for breaking things).
const RANGE := "res://modules/range/range_module.gd"

## `--library` opens the library straight away, once per launch (Back then goes to the menu).
static var _library_from_args := OS.get_cmdline_user_args().has("--library")


func _ready() -> void:
	# Before anything reads the profile or opens a save.
	var moved := UserDataMove.run()
	if moved > 0:
		Log.info(&"boot", "copied %d player files from the old Outpost folder" % moved)
	if _library_from_args and _library_available():
		_library_from_args = false
		_show_library()
		return
	if Net.awaiting_menu:
		_show_menu()
		return
	# Before modules load, so they already see this instance as a client of its own server.
	Net.start_solo()
	_start_session()


func _show_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var menu := MainMenu.new()
	menu.name = "MainMenu"
	menu.message = Net.menu_message
	menu.has_library = _library_available()
	menu.has_range = Features.is_enabled(&"range") and ResourceLoader.exists(RANGE)
	add_child(menu)
	menu.solo_requested.connect(func() -> void: _begin(menu, func() -> void:
		Net.awaiting_menu = false
		Net.start_solo()))
	menu.host_requested.connect(func(port: int) -> void: _begin(menu, Net.start_host.bind(port)))
	menu.join_requested.connect(func(host: String, port: int) -> void: _begin(menu, Net.join.bind(host, port)))
	menu.range_requested.connect(func() -> void: _begin(menu, func() -> void:
		Net.awaiting_menu = false
		Net.extra_args = PackedStringArray(["--range", "--no-save"])
		Net.start_solo()))
	menu.library_requested.connect(func() -> void:
		menu.queue_free()
		_show_library())


static func _library_available() -> bool:
	return Features.is_enabled(&"voxkit") and ResourceLoader.exists(LIBRARY)


## Client only, no session: leaving it reloads this scene, which shows the menu again.
func _show_library() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var library: Control = (load(LIBRARY) as GDScript).new()
	library.name = "AssetLibrary"
	library.connect(&"closed", func() -> void: get_tree().reload_current_scene())
	add_child(library)


func _begin(menu: MainMenu, start: Callable) -> void:
	menu.queue_free()
	Net.menu_message = ""
	start.call()
	# A start that failed has already asked for the menu again.
	if not Net.awaiting_menu:
		_start_session()


func _start_session() -> void:
	if Net.interactive:
		var overlay := SessionOverlay.new()
		overlay.name = "SessionOverlay"
		add_child(overlay)
	var modules_node := Node.new()
	modules_node.name = "Modules"
	add_child(modules_node)
	var to_load := ModuleLoader.resolve(ModuleLoader.discover(MODULES_ROOT), Features.is_enabled)
	var loaded: PackedStringArray = []
	for info in to_load:
		var script: Variant = load(info.dir.path_join(info.entry))
		if not script is GDScript:
			Log.error(&"modules", "%s: entry '%s' is not a script" % [info.id, info.entry])
			continue
		var gd: GDScript = script
		var node: Variant = gd.new()
		if not node is Node:
			Log.error(&"modules", "%s: entry '%s' must extend Node" % [info.id, info.entry])
			continue
		var module_node: Node = node
		module_node.name = String(info.id)
		modules_node.add_child(module_node)
		loaded.append(String(info.id))
	Log.info(&"boot", "loaded modules: %s" % (", ".join(loaded) if loaded.size() > 0 else "(none)"))

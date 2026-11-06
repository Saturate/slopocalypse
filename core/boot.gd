extends Node
## Main scene root. Loads every enabled module as a child of `Modules`.

const MODULES_ROOT := "res://modules"


func _ready() -> void:
	# Before modules load, so they already see this instance as a client of its own server.
	Net.start_solo()
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

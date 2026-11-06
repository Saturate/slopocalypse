extends SceneTree
## Compiles scripts inside a running project so autoload names resolve, which
## `--check-only` cannot do. Paths come after `--`; parse errors land in the log.


func _initialize() -> void:
	var failed := 0
	for path in OS.get_cmdline_user_args():
		var script: Variant = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if not script is Script:
			printerr("ERROR: could not load %s" % path)
			failed += 1
			continue
		var s: Script = script
		if not s.can_instantiate():
			printerr("ERROR: %s does not compile" % path)
			failed += 1
	print("checked %d script(s), %d failed" % [OS.get_cmdline_user_args().size(), failed])
	quit(1 if failed > 0 else 0)

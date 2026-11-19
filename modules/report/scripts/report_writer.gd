class_name ReportWriter
extends RefCounted
## Writes a report: one zip holding `report.json` (what happened, on what machine, where in
## the game) and whatever files go with it (screenshot, logs, perf logs). Bug reports and the
## benchmark write the same shape, and `tools/report.ts` reads it.


## `report` as report.json, then `files` (path in the zip -> bytes), to `path`.
static func write(path: String, report: Dictionary, files: Dictionary) -> Error:
	var zip := ZIPPacker.new()
	var err := zip.open(path)
	if err != OK:
		return err
	err = _add(zip, "report.json", JSON.stringify(report, "  ").to_utf8_buffer())
	for name: String in files:
		if err != OK:
			break
		err = _add(zip, name, files[name])
	zip.close()
	return err


## The last `max_bytes` of a file (the newest lines of a log), or nothing if it can't be read.
## Starts on a whole line where the cut falls inside one.
static func tail_of(path: String, max_bytes: int) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var length := f.get_length()
	var start := maxi(0, length - max_bytes)
	f.seek(start)
	var bytes := f.get_buffer(length - start)
	f.close()
	if start > 0:
		var newline := bytes.find(10)
		if newline >= 0:
			bytes = bytes.slice(newline + 1)
	return bytes


## `slopocalypse-report-YYYYMMDD-HHMMSS.zip` for a `Time` datetime dictionary.
static func file_name(time: Dictionary) -> String:
	return "slopocalypse-report-%04d%02d%02d-%02d%02d%02d.zip" % [time["year"], time["month"], time["day"], time["hour"], time["minute"], time["second"]]


## The machine and build: what decides whether a hitch is ours or the hardware's.
static func system_info() -> Dictionary:
	var memory := OS.get_memory_info()
	var screen := DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i.ZERO
	var window := DisplayServer.window_get_size() if DisplayServer.get_name() != "headless" else Vector2i.ZERO
	return {
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"engine": Engine.get_version_info().get("string", ""),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"distribution": OS.get_distribution_name(),
		"cpu": OS.get_processor_name(),
		"cpu_cores": OS.get_processor_count(),
		"memory_mb": int(memory.get("physical", 0)) / (1024 * 1024),
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"gpu_api": RenderingServer.get_video_adapter_api_version(),
		"gpu_driver": OS.get_video_adapter_driver_info(),
		"renderer": "%s (%s)" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name()],
		"screen": [screen.x, screen.y],
		"window": [window.x, window.y],
		"window_mode": DisplayServer.window_get_mode() if DisplayServer.get_name() != "headless" else -1,
		"locale": OS.get_locale(),
	}


static func _add(zip: ZIPPacker, name: String, bytes: PackedByteArray) -> Error:
	var err := zip.start_file(name)
	if err != OK:
		return err
	err = zip.write_file(bytes)
	zip.close_file()
	return err

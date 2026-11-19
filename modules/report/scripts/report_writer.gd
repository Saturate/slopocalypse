class_name ReportWriter
extends RefCounted
## Writes a report: one zip holding `report.json` (what happened, on what machine, where in
## the game) and whatever files go with it (screenshot, logs, perf logs). Bug reports and the
## benchmark write the same shape, and `tools/report.ts` reads it.

## Command-line flags safe to share: how the game was started, never where it connected,
## what it is called or where files are (those carry addresses and the OS user name).
const PUBLIC_ARGS: Array[String] = ["--solo", "--flags=", "--all-optional-off", "--world=", "--start=", "--bot=", "--bench=", "--uncapped", "--range", "--crowd=", "--debug-api"]
## Written over in shared logs: IPv4 addresses, IPv6 ones with a `::` in them, and host
## names given with a port (`name.example.org:7777`).
const ADDRESSES: Array[String] = [
	"\\b\\d{1,3}(\\.\\d{1,3}){3}\\b",
	"(?i)\\[?[0-9a-f]*::[0-9a-f:]*\\]?",
	"(?i)\\b[a-z0-9-]+(\\.[a-z0-9-]+)*\\.[a-z]{2,}(?=:\\d)",
]
## An account name shorter than this is too likely to be an ordinary word to write over.
const MIN_ACCOUNT_NAME := 3



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


## The `args` worth sharing, from `PUBLIC_ARGS`.
static func public_args(args: PackedStringArray) -> Array[String]:
	var out: Array[String] = []
	for arg in args:
		for allowed in PUBLIC_ARGS:
			if arg == allowed or (allowed.ends_with("=") and arg.begins_with(allowed)):
				out.append(arg)
				break
	return out


## `text` fit to send: `folders` (home, user data; either slash) become `<folder>`, the OS
## `account` name becomes `<user>`, and addresses and the host after "connecting to" become
## `<address>`.
static func scrub(text: String, folders: Array[String], account := "") -> String:
	for folder in folders:
		if folder.is_empty():
			continue
		for form in [folder, folder.replace("\\", "/"), folder.replace("/", "\\")]:
			text = text.replace(form, "<folder>")
	text = RegEx.create_from_string("connecting to [^\\s:]+").sub(text, "connecting to <address>", true)
	for pattern in ADDRESSES:
		text = RegEx.create_from_string(pattern).sub(text, "<address>", true)
	if account.length() >= MIN_ACCOUNT_NAME:
		text = text.replace(account, "<user>")
	return text


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

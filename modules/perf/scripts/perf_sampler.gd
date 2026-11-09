class_name PerfSampler
extends RefCounted
## Collects frame times over one sample window and summarises them. Pure: the perf module
## feeds it and adds the engine's own monitors.

var _frames := PackedFloat32Array()


func add_frame(ms: float) -> void:
	_frames.append(ms)


## {frames, frame_ms_mean, frame_ms_p95, frame_ms_max} for the window so far, then empties it.
func take() -> Dictionary:
	var out := {"frames": _frames.size(), "frame_ms_mean": 0.0, "frame_ms_p95": 0.0, "frame_ms_max": 0.0}
	if _frames.is_empty():
		return out
	var sorted := _frames.duplicate()
	sorted.sort()
	var sum := 0.0
	for ms in sorted:
		sum += ms
	out["frame_ms_mean"] = sum / sorted.size()
	# Nearest rank: the smallest time that 95% of frames are at or under.
	out["frame_ms_p95"] = sorted[clampi(ceili(sorted.size() * 0.95) - 1, 0, sorted.size() - 1)]
	out["frame_ms_max"] = sorted[sorted.size() - 1]
	_frames.clear()
	return out


## Log files (`<role>-<yyyymmdd>-<hhmmss>.ndjson`) to delete so at most `keep` remain,
## oldest first. Other files are left alone.
static func to_prune(names: Array[String], keep: int) -> Array[String]:
	var logs: Array[String] = names.filter(func(n: String) -> bool: return n.ends_with(".ndjson") and n.contains("-"))
	logs.sort_custom(func(a: String, b: String) -> bool: return _stamp(a) < _stamp(b))
	return logs.slice(0, maxi(logs.size() - keep, 0))


static func _stamp(name: String) -> String:
	return name.substr(name.find("-") + 1)

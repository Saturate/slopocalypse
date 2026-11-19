class_name BenchmarkStats
extends RefCounted
## The numbers a benchmark run ends with, from its frame times and the perf log. Pure.


## {frames, fps_mean, fps_low_1pct, frame_ms_mean, frame_ms_p95, frame_ms_worst}.
## The 1 % low is the frame rate over the slowest hundredth of frames: what stutter feels like.
static func summarise(frames_ms: PackedFloat32Array) -> Dictionary:
	var out := {"frames": frames_ms.size(), "fps_mean": 0.0, "fps_low_1pct": 0.0, "frame_ms_mean": 0.0, "frame_ms_p95": 0.0, "frame_ms_worst": 0.0}
	if frames_ms.is_empty():
		return out
	var sorted := frames_ms.duplicate()
	sorted.sort()
	var total := 0.0
	for ms in sorted:
		total += ms
	var mean := total / sorted.size()
	var slowest := maxi(1, sorted.size() / 100)
	var slow_total := 0.0
	for i in slowest:
		slow_total += sorted[sorted.size() - 1 - i]
	out["frame_ms_mean"] = snappedf(mean, 0.01)
	out["fps_mean"] = snappedf(1000.0 / mean, 0.1) if mean > 0.0 else 0.0
	out["fps_low_1pct"] = snappedf(1000.0 / (slow_total / slowest), 0.1) if slow_total > 0.0 else 0.0
	out["frame_ms_p95"] = snappedf(sorted[clampi(ceili(sorted.size() * 0.95) - 1, 0, sorted.size() - 1)], 0.01)
	out["frame_ms_worst"] = snappedf(sorted[-1], 0.01)
	return out


## The `count` slowest spike lines of a perf log between `from` and `to` (seconds of the
## log's clock), slowest first: [{t, ms, zones, compiles}].
static func worst_hitches(log: String, from: float, to: float, count: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	# An instance parse: the static one logs an engine error for a line cut short at exit.
	var json := JSON.new()
	for line in log.split("\n", false):
		if json.parse(line) != OK:
			continue
		var rec: Variant = json.data
		if not rec is Dictionary or not (rec as Dictionary).has("spike_ms"):
			continue
		var t := float(rec.get("t", -1.0))
		if t < from or t > to:
			continue
		found.append({"t": t, "ms": float(rec["spike_ms"]), "zones": rec.get("zones", {}), "compiles": rec.get("compiles", {})})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["ms"]) > float(b["ms"]))
	return found.slice(0, count)

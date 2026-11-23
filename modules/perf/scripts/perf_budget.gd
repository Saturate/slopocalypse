class_name PerfBudget
extends RefCounted
## Where a frame's time goes, from what the perf module measured over a sample window. Pure.
##
## The parts add up to the frame on the main thread:
##   scripts  every moment some profile zone (core/prof.gd) was running, nested zones once
##   physics  the physics ticks outside zones: nodes' _physics_process no zone covers, the
##            deferred calls, timers and tweens flushed after them, and the engine's step
##            (with its sync and body callbacks between two ticks of one frame), and the
##            network receive Godot polls right after the last tick (unzoned RPC handlers)
##   render   RenderingServer drawing the frame on the main thread, waiting for the GPU
##            included when it is behind (the default thread model; a separate render
##            thread would draw outside this)
##   other    the rest: unzoned _process work (animation trees, skeletons, particles, UI),
##            the first tick's physics sync and callbacks, input and any idle wait
## GPU time runs alongside on the graphics card, so it is shown beside the stack, not in it.

const PARTS: Array[String] = ["scripts_ms", "physics_ms", "render_ms"]


## {frame_ms, scripts_ms, physics_ms, render_ms, other_ms} per frame. `frame_ms` is the mean
## frame time; the parts are the window's totals in microseconds over `frames`.
static func split(frame_ms: float, frames: int, scripts_usec: int, physics_usec: int, render_usec: int) -> Dictionary:
	var out := {"frame_ms": 0.0, "scripts_ms": 0.0, "physics_ms": 0.0, "render_ms": 0.0, "other_ms": 0.0}
	if frames <= 0:
		return out
	# To the microsecond the zones are timed in: an uncapped server runs thousands of frames a
	# second, and bench.ts multiplies these back up to a cost per tick.
	out["frame_ms"] = snappedf(frame_ms, 0.001)
	var totals := [scripts_usec, physics_usec, render_usec]
	var used := 0.0
	for i in PARTS.size():
		var ms := float(totals[i]) / 1000.0 / frames
		out[PARTS[i]] = snappedf(ms, 0.001)
		used += ms
	# Parts are measured on their own clocks, so they can add to a hair over the frame.
	out["other_ms"] = snappedf(maxf(frame_ms - used, 0.0), 0.001)
	return out


## The module a zone belongs to: its prefix, or for an EventBus handler
## (`event/<topic>/<module>`) the module that handled it.
static func module_of(zone: String) -> String:
	var parts := zone.split("/")
	if parts[0] == "event" and parts.size() >= 3:
		return parts[-1]
	return parts[0]


## {module: ms per frame} from a sample's zones ({zone: {ms}} over the window), biggest first.
## Zones inside zones of the same module count twice, so a module can read high.
static func by_module(zones: Dictionary, frames: int) -> Dictionary:
	var totals: Dictionary[String, float] = {}
	for zone: String in zones:
		var z: Variant = zones[zone]
		if not z is Dictionary:
			continue
		var module := module_of(zone)
		totals[module] = totals.get(module, 0.0) + float((z as Dictionary).get("ms", 0.0))
	var names := totals.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return totals[a] > totals[b])
	var out := {}
	for name: String in names:
		out[name] = snappedf(totals[name] / maxi(frames, 1), 0.001)
	return out


## One line for the overlay: the frame stacked into its parts, the GPU beside it (negative
## when the driver cannot time it).
static func line(budget: Dictionary, gpu_ms: float) -> String:
	var gpu := "gpu %.1f" % gpu_ms if gpu_ms >= 0.0 else "gpu untimed"
	return "frame %.1f = scripts %.1f + physics %.1f + render %.1f + other %.1f   %s" % [budget.get("frame_ms", 0.0), budget.get("scripts_ms", 0.0), budget.get("physics_ms", 0.0), budget.get("render_ms", 0.0), budget.get("other_ms", 0.0), gpu]

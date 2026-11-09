class_name Prof
extends RefCounted
## Named timers ("zones") for our own code, so the perf log can say which functions cost
## what. Static, so any script can use it without depending on the perf module:
##     var t := Prof.start()
##     ...the work...
##     Prof.stop(&"world/voxels", t)
## Every call adds to that zone's total, call count and worst call until `take()` (the perf
## module does that once per sample). A zone is about 1 microsecond of overhead.

static var _total: Dictionary[StringName, int] = {}
static var _calls: Dictionary[StringName, int] = {}
static var _worst: Dictionary[StringName, int] = {}
## The same, since the last frame was taken: what a slow frame was busy with.
static var _frame: Dictionary[StringName, int] = {}


static func start() -> int:
	return Time.get_ticks_usec()


static func stop(zone: StringName, started: int) -> void:
	var spent := maxi(Time.get_ticks_usec() - started, 0)
	_total[zone] = _total.get(zone, 0) + spent
	_calls[zone] = _calls.get(zone, 0) + 1
	# Always written: a zone faster than a microsecond spends 0 and must still have an entry.
	_worst[zone] = maxi(_worst.get(zone, 0), spent)
	_frame[zone] = _frame.get(zone, 0) + spent


## {zone: ms} since the last call, the `count` most expensive, then starts again.
static func take_frame(count: int) -> Dictionary:
	var zones := _frame.keys()
	zones.sort_custom(func(a: StringName, b: StringName) -> bool: return _frame[a] > _frame[b])
	var out := {}
	for zone: StringName in zones.slice(0, count):
		out[String(zone)] = snappedf(_frame[zone] / 1000.0, 0.001)
	_frame.clear()
	return out


## {zone: {ms, calls, max_ms}} since the last take, then starts again.
static func take() -> Dictionary:
	var out := {}
	for zone: StringName in _total:
		out[String(zone)] = {"ms": snappedf(_total[zone] / 1000.0, 0.001), "calls": _calls[zone], "max_ms": snappedf(_worst[zone] / 1000.0, 0.001)}
	_total.clear()
	_calls.clear()
	_worst.clear()
	return out

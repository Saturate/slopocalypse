class_name Prof
extends RefCounted
## Named timers ("zones") for our own code, so the perf log can say which functions cost
## what. Static, so any script can use it without depending on the perf module:
##     var t := Prof.start()
##     ...the work...
##     Prof.stop(&"world/voxels", t)
## Every call adds to that zone's total, call count and worst call until `take()` (the perf
## module does that once per sample). A zone is about 1 microsecond of overhead.
##
## Zones nest (an EventBus handler's zone runs inside the zone that published), so their
## totals overlap. `covered_usec()` is how long any zone was running, each moment counted
## once: the frame budget's "scripts" share.

static var _total: Dictionary[StringName, int] = {}
static var _calls: Dictionary[StringName, int] = {}
static var _worst: Dictionary[StringName, int] = {}
## The same, since the last frame was taken: what a slow frame was busy with.
static var _frame: Dictionary[StringName, int] = {}
## Microseconds any zone was running, since the start: only ever grows.
static var _covered := 0
## The covered stretches closed this frame, in the order they closed, merged where they
## overlap: an outer zone closes after the zones inside it and swallows them.
static var _starts := PackedInt64Array()
static var _ends := PackedInt64Array()
## Kept this many stretches before forgetting the oldest half. Only an outer zone holding more
## closed zones than that would count the forgotten ones twice.
const MAX_STRETCHES := 64
const KEEP_STRETCHES := 32


## A zone must not span an `await`: covered time is merged frame by frame, and a zone left
## open across frames would swallow everything that ran in between.
static func start() -> int:
	return Time.get_ticks_usec()


static func stop(zone: StringName, started: int) -> void:
	stop_at(zone, started, Time.get_ticks_usec())


## `stop` with the end given: tests use it to lay zones out on the clock.
static func stop_at(zone: StringName, started: int, ended: int) -> void:
	var spent := maxi(ended - started, 0)
	_cover(mini(started, ended), ended)
	_total[zone] = _total.get(zone, 0) + spent
	_calls[zone] = _calls.get(zone, 0) + 1
	# Always written: a zone faster than a microsecond spends 0 and must still have an entry.
	_worst[zone] = maxi(_worst.get(zone, 0), spent)
	_frame[zone] = _frame.get(zone, 0) + spent


## How long any zone has run since the start, nested zones counted once. Read it twice and
## subtract to get the scripts' share of a stretch of time.
static func covered_usec() -> int:
	return _covered


static func _cover(started: int, ended: int) -> void:
	var from := started
	var to := ended
	var swallowed := 0
	# Stretches closed earlier that end after this one began lie inside it (or overlap it):
	# merge them, and count only what the merged stretch adds.
	while not _ends.is_empty() and _ends[-1] > from:
		var last := _ends.size() - 1
		swallowed += _ends[last] - _starts[last]
		from = mini(from, _starts[last])
		to = maxi(to, _ends[last])
		_starts.resize(last)
		_ends.resize(last)
	_starts.append(from)
	_ends.append(to)
	_covered += maxi(to - from - swallowed, 0)
	if _starts.size() > MAX_STRETCHES:
		_starts = _starts.slice(_starts.size() - KEEP_STRETCHES)
		_ends = _ends.slice(_ends.size() - KEEP_STRETCHES)


## {zone: ms} since the last call, the `count` most expensive, then starts again.
static func take_frame(count: int) -> Dictionary:
	var zones := _frame.keys()
	zones.sort_custom(func(a: StringName, b: StringName) -> bool: return _frame[a] > _frame[b])
	var out := {}
	for zone: StringName in zones.slice(0, count):
		out[String(zone)] = snappedf(_frame[zone] / 1000.0, 0.001)
	_frame.clear()
	# No zone is open between frames, so none can swallow these any more.
	_starts.clear()
	_ends.clear()
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

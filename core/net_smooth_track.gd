class_name NetSmoothTrack
extends RefCounted
## The recent server updates of one remote thing, stamped with when they arrived, and where it
## should be shown at any moment: `delay` seconds in the past, blended between the updates
## either side. Showing the past costs a little lag but means there is nearly always a newer
## update to blend toward, so uneven packets don't make it stop and jump.
##
## Values are floats or Vector3s, one per property; `kinds` says whether each is a plain value
## or an angle (blended the short way round, per axis for a Vector3).

const LINEAR := 0
const ANGLE := 1

var delay := 0.05
## How long it keeps moving along its last motion once updates stop coming.
var extrapolate := 0.1
## A jump longer than this between two updates of value `snap_index` is a teleport.
var snap_distance := 5.0
## Which value is the position checked for teleports; -1 for none.
var snap_index := -1
var kinds: Array[int] = []

var _times: Array[float] = []
var _values: Array[Array] = []


func size() -> int:
	return _times.size()


func push(time: float, values: Array) -> void:
	if not _times.is_empty():
		if snap_index >= 0 and _teleported(_values[-1][snap_index], values[snap_index]):
			_times.clear()
			_values.clear()
		elif time <= _times[-1]:
			# Two arrived in the same frame: the newer one wins rather than blending over no time.
			_values[-1] = values.duplicate()
			return
	_times.append(time)
	_values.append(values.duplicate())


## Values to show at `now`; empty before the first update.
func sample(now: float) -> Array:
	if _times.is_empty():
		return []
	var t := now - delay
	# Drop what is wholly in the past: the newest update at or before `t` is still needed.
	while _times.size() > 2 and _times[1] <= t:
		_times.pop_front()
		_values.pop_front()
	if _times.size() == 1 or t <= _times[0]:
		return _values[0 if t <= _times[0] else -1].duplicate()
	if t >= _times[-1]:
		var a := _values[-2]
		var b := _values[-1]
		var span := _times[-1] - _times[-2]
		var past := minf(t - _times[-1], extrapolate)
		return _mix(a, b, 1.0 + past / span)
	for i in range(_times.size() - 1):
		if t < _times[i + 1]:
			return _mix(_values[i], _values[i + 1], (t - _times[i]) / (_times[i + 1] - _times[i]))
	return _values[-1].duplicate()


func _mix(a: Array, b: Array, k: float) -> Array:
	var out: Array = []
	for i in a.size():
		out.append(_blend(a[i], b[i], k, kinds[i] if i < kinds.size() else LINEAR))
	return out


## Past 1 it carries on the same way: `lerp_angle` stops at the end, so angles step by hand.
static func _blend(a: Variant, b: Variant, k: float, kind: int) -> Variant:
	if a is Vector3:
		var va: Vector3 = a
		var vb: Vector3 = b
		if kind == ANGLE:
			return Vector3(_angle(va.x, vb.x, k), _angle(va.y, vb.y, k), _angle(va.z, vb.z, k))
		return va + (vb - va) * k
	if a is float:
		if kind == ANGLE:
			return _angle(a, b, k)
		return float(a) + (float(b) - float(a)) * k
	return b if k >= 0.5 else a


static func _angle(a: float, b: float, k: float) -> float:
	return a + angle_difference(a, b) * k


func _teleported(a: Variant, b: Variant) -> bool:
	return a is Vector3 and b is Vector3 and (a as Vector3).distance_to(b) > snap_distance

class_name MinHeap
extends RefCounted
## A min-heap of (key, value) pairs: the priority flood that finds ponds and the road
## router both take the cheapest next step first.

var _keys := PackedFloat32Array()
var _values := PackedInt32Array()


func is_empty() -> bool:
	return _keys.is_empty()


func push(key: float, value: int) -> void:
	_keys.append(key)
	_values.append(value)
	var i := _keys.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if _keys[parent] <= _keys[i]:
			break
		_swap(i, parent)
		i = parent


## The value with the smallest key, taken off.

func pop() -> int:
	var top := _values[0]
	var last := _keys.size() - 1
	_swap(0, last)
	_keys.resize(last)
	_values.resize(last)
	var i := 0
	while true:
		var smallest := i
		for c in [2 * i + 1, 2 * i + 2]:
			if c < _keys.size() and _keys[c] < _keys[smallest]:
				smallest = c
		if smallest == i:
			break
		_swap(i, smallest)
		i = smallest
	return top


func _swap(a: int, b: int) -> void:
	var k := _keys[a]
	_keys[a] = _keys[b]
	_keys[b] = k
	var v := _values[a]
	_values[a] = _values[b]
	_values[b] = v

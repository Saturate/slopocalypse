extends SceneTree
## Are two .tscn files the same scene, allowing for float rounding? Builders run Godot's own
## sin, cos and quaternion maths, whose last bits differ between Windows, Linux and macOS, so
## a rebuild on another OS can change bytes without changing the scene.
##   godot --headless --path . -s res://tools/gd/scene_equal.gd -- <a.tscn> <b.tscn>
## Prints SAME or DIFFERENT: <where>, and exits 0 for the same, 1 for different.

## Absolute and relative tolerance: well above float32 rounding, far below anything visible.
const TOLERANCE := 1e-4

var _seen: Dictionary = {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("usage: -- <a.tscn> <b.tscn>")
		quit(2)
		return
	var a := ResourceLoader.load(args[0], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var b := ResourceLoader.load(args[1], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if a == null or b == null:
		printerr("cannot load %s" % (args[0] if a == null else args[1]))
		quit(2)
		return
	var na := a.instantiate()
	var nb := b.instantiate()
	var where := _nodes(na, nb, ".")
	na.free()
	nb.free()
	if where.is_empty():
		print("SAME")
		quit(0)
	else:
		print("DIFFERENT: " + where)
		quit(1)


func _nodes(a: Node, b: Node, path: String) -> String:
	if a.get_class() != b.get_class() or a.name != b.name:
		return "%s: %s %s vs %s %s" % [path, a.get_class(), a.name, b.get_class(), b.name]
	var where := _object(a, b, path)
	if not where.is_empty():
		return where
	if a.get_child_count() != b.get_child_count():
		return "%s: %d vs %d children" % [path, a.get_child_count(), b.get_child_count()]
	for i in a.get_child_count():
		where = _nodes(a.get_child(i), b.get_child(i), path + "/" + String(a.get_child(i).name))
		if not where.is_empty():
			return where
	return ""


func _object(a: Object, b: Object, path: String) -> String:
	if a.get_class() != b.get_class():
		return "%s: %s vs %s" % [path, a.get_class(), b.get_class()]
	var key := "%d:%d" % [a.get_instance_id(), b.get_instance_id()]
	if _seen.has(key):
		return ""
	_seen[key] = true
	if a is Mesh:
		var where := _meshes(a as Mesh, b as Mesh, path)
		if not where.is_empty():
			return where
	for prop: Dictionary in a.get_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_STORAGE == 0:
			continue
		var name: String = prop["name"]
		# Mesh surfaces are compared as decoded arrays above; their packed bytes are not.
		if a is Mesh and name.begins_with("_surfaces"):
			continue
		if name == "script" or name == "owner":
			continue
		var where := _value(a.get(name), b.get(name), path + ":" + name)
		if not where.is_empty():
			return where
	return ""


func _meshes(a: Mesh, b: Mesh, path: String) -> String:
	if a.get_surface_count() != b.get_surface_count():
		return "%s: %d vs %d surfaces" % [path, a.get_surface_count(), b.get_surface_count()]
	for s in a.get_surface_count():
		var where := _value(a.surface_get_arrays(s), b.surface_get_arrays(s), "%s/surface%d" % [path, s])
		if not where.is_empty():
			return where
		where = _value(a.surface_get_material(s), b.surface_get_material(s), "%s/surface%d/material" % [path, s])
		if not where.is_empty():
			return where
	return ""


func _value(a: Variant, b: Variant, path: String) -> String:
	if typeof(a) != typeof(b):
		return "%s: %s vs %s" % [path, type_string(typeof(a)), type_string(typeof(b))]
	match typeof(a):
		TYPE_FLOAT:
			return "" if _close(a, b) else "%s: %s vs %s" % [path, a, b]
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_QUATERNION, TYPE_COLOR, TYPE_PLANE, TYPE_RECT2, TYPE_AABB, TYPE_BASIS, TYPE_TRANSFORM2D, TYPE_TRANSFORM3D, TYPE_PROJECTION:
			return "" if _floats_close(_flatten(a), _flatten(b)) else "%s: %s vs %s" % [path, a, b]
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			if a.size() != b.size():
				return "%s: %d vs %d items" % [path, a.size(), b.size()]
			for i in a.size():
				if not _floats_close(_flatten(a[i]), _flatten(b[i])):
					return "%s[%d]: %s vs %s" % [path, i, a[i], b[i]]
			return ""
		TYPE_ARRAY:
			if (a as Array).size() != (b as Array).size():
				return "%s: %d vs %d items" % [path, a.size(), b.size()]
			for i in (a as Array).size():
				var where := _value(a[i], b[i], "%s[%d]" % [path, i])
				if not where.is_empty():
					return where
			return ""
		TYPE_DICTIONARY:
			if (a as Dictionary).keys() != (b as Dictionary).keys():
				return "%s: keys %s vs %s" % [path, a.keys(), b.keys()]
			for k: Variant in a:
				var where := _value(a[k], b[k], "%s.%s" % [path, k])
				if not where.is_empty():
					return where
			return ""
		TYPE_OBJECT:
			if a == null or b == null:
				return "" if a == b else "%s: %s vs %s" % [path, a, b]
			# The same file on both sides (external resources) is the same thing.
			if a is Resource and (a as Resource).resource_path.begins_with("res://") and not (a as Resource).resource_path.contains("::"):
				return "" if (a as Resource).resource_path == (b as Resource).resource_path else "%s: %s vs %s" % [path, a.resource_path, b.resource_path]
			return _object(a, b, path)
		_:
			return "" if a == b else "%s: %s vs %s" % [path, a, b]


func _close(a: float, b: float) -> bool:
	return absf(a - b) <= TOLERANCE * maxf(1.0, maxf(absf(a), absf(b)))


func _floats_close(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not _close(a[i], b[i]):
			return false
	return true


func _flatten(v: Variant) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	match typeof(v):
		TYPE_FLOAT, TYPE_INT:
			out.append(float(v))
		TYPE_VECTOR2:
			out.append_array([v.x, v.y])
		TYPE_VECTOR3:
			out.append_array([v.x, v.y, v.z])
		TYPE_VECTOR4, TYPE_QUATERNION:
			out.append_array([v.x, v.y, v.z, v.w])
		TYPE_COLOR:
			out.append_array([v.r, v.g, v.b, v.a])
		TYPE_PLANE:
			out.append_array([v.normal.x, v.normal.y, v.normal.z, v.d])
		TYPE_RECT2:
			out.append_array(_flatten(v.position) + _flatten(v.size))
		TYPE_AABB:
			out.append_array(_flatten(v.position) + _flatten(v.size))
		TYPE_BASIS:
			out.append_array(_flatten(v.x) + _flatten(v.y) + _flatten(v.z))
		TYPE_TRANSFORM2D:
			out.append_array(_flatten(v.x) + _flatten(v.y) + _flatten(v.origin))
		TYPE_TRANSFORM3D:
			out.append_array(_flatten(v.basis) + _flatten(v.origin))
		TYPE_PROJECTION:
			out.append_array(_flatten(v.x) + _flatten(v.y) + _flatten(v.z) + _flatten(v.w))
	return out

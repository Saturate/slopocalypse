class_name SceneBuilder
extends RefCounted
## Saves node trees built in code as .tscn files without Godot's silent failure modes:
## nodes without an owner are dropped, instanced scenes get inlined if you own their
## children, and every save writes fresh random ids so the file churns in git.


class Result:
	var error: Error = OK
	var message: String = ""


static func count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += count_nodes(child)
	return total


## Owns every node to `root`, but stops at instanced scenes: owning their children would
## inline the whole sub-scene (a GLB becomes megabytes of text).
static func set_owner_recursive(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		if child.scene_file_path.is_empty():
			set_owner_recursive(child, root)


static func pack_and_save(root: Node, path: String, set_owners: bool = true) -> Result:
	var result := Result.new()
	if set_owners:
		set_owner_recursive(root, root)
	_stabilise_subresource_ids(root, root)
	var expected := _count_built(root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		result.error = err
		result.message = "%s: pack failed with %s" % [path, error_string(err)]
		return result
	var probe := packed.instantiate()
	var got := _count_built(probe)
	probe.free()
	if got != expected:
		result.error = ERR_INVALID_DATA
		result.message = "%s: %d of %d nodes would be dropped (missing owner?)" % [path, expected - got, expected]
		return result
	var existing_uid := ResourceLoader.get_resource_uid(path) if ResourceLoader.exists(path) else ResourceUID.INVALID_ID
	err = ResourceSaver.save(packed, path)
	if err != OK:
		result.error = err
		result.message = "%s: save failed with %s" % [path, error_string(err)]
		return result
	if existing_uid != ResourceUID.INVALID_ID:
		ResourceSaver.set_uid(path, existing_uid)
	_stabilise_node_ids(path)
	return result


## Counts every node that should end up in the file: all descendants, with an instanced
## scene counted as one node because its insides live in its own file.
static func _count_built(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += 1 if not child.scene_file_path.is_empty() else _count_built(child)
	return total


## Godot 4.6+ writes a random `unique_id` on every node at each save and has no API to set
## it, so rewrite it as a hash of the node's path: stable across builds, unique per scene.
static func _stabilise_node_ids(path: String) -> void:
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var attr := RegEx.create_from_string('(name|parent)="([^"]*)"')
	var uid := RegEx.create_from_string("unique_id=[0-9]+")
	for i in lines.size():
		var line := lines[i]
		if not line.begins_with("[node ") or uid.search(line) == null:
			continue
		var name := ""
		var parent := ""
		for m in attr.search_all(line):
			if m.get_string(1) == "name":
				name = m.get_string(2)
			else:
				parent = m.get_string(2)
		var node_path := name if parent.is_empty() else (parent + "/" + name)
		lines[i] = uid.sub(line, "unique_id=%d" % (node_path.hash() & 0x7FFFFFFF))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()


## Sub-resources embedded in the scene get ids derived from where they are used, instead
## of random ones.
static func _stabilise_subresource_ids(node: Node, root: Node) -> void:
	var where := String(root.get_path_to(node))
	for prop in node.get_property_list():
		if not (prop["usage"] & PROPERTY_USAGE_STORAGE):
			continue
		var value: Variant = node.get(prop["name"])
		if value is Resource:
			_stabilise_resource(value, where + ":" + String(prop["name"]))
	for child in node.get_children():
		if child.scene_file_path.is_empty():
			_stabilise_subresource_ids(child, root)


static func _stabilise_resource(res: Resource, where: String) -> void:
	# Resources with their own file are referenced, not embedded.
	if not res.resource_path.is_empty() and not res.resource_path.contains("::"):
		return
	res.set_scene_unique_id("%s_%x" % [res.get_class(), where.hash() & 0xFFFFFF])
	for prop in res.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_STORAGE:
			var value: Variant = res.get(prop["name"])
			if value is Resource:
				_stabilise_resource(value, where + "/" + String(prop["name"]))

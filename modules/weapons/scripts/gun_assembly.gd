class_name GunAssembly
extends RefCounted
## Guns from parts: reads the catalogue and builds in `parts.json`, has Rust
## (`WeaponBuild`) check a build and compute its stats, and puts together the visible gun
## with each part's mesh on its parent's mount point.

const DATA := "res://modules/weapons/data/parts.json"

static var _data: Dictionary = {}
## Set by captures and tests to equip a build without command-line arguments.
static var override_build := ""


static func _load() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = Data.load_json(DATA)
		_data = parsed if parsed is Dictionary else {}
	return _data


## Part id -> part data.
static func catalogue() -> Dictionary:
	return _load().get("parts", {})


static func build_names() -> Array:
	return (_load().get("builds", {}) as Dictionary).keys()


static func default_build() -> String:
	return str(_load().get("default_build", ""))


## The build everyone carries: the default, or `--build=NAME` on the command line (a dev
## hook to try builds until the modding screen picks per player; solo passes it on to its
## server so stats match).
static func chosen_build() -> String:
	if not override_build.is_empty():
		return override_build
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--build="):
			var wanted := arg.trim_prefix("--build=")
			if build_names().has(wanted):
				return wanted
	return default_build()


static func default_secondary() -> String:
	return str(_load().get("default_secondary", ""))


## The receiver's data for a build, or empty.
static func receiver_of(slots: Dictionary) -> Dictionary:
	return catalogue().get(str(slots.get("receiver", "")), {})


## Which weapon slot a build goes in, from its receiver ("primary" unless it says).
static func weapon_slot_of(slots: Dictionary) -> String:
	return str(receiver_of(slots).get("weapon_slot", "primary"))


## Where the model sits relative to the hands' socket: a pistol is held further out and
## higher than a rifle's receiver.
static func hold_offset(slots: Dictionary) -> Vector3:
	var receiver := receiver_of(slots)
	return _vec(receiver["hold"]) if receiver.has("hold") else Vector3.ZERO


## Slot -> part id for a named build, or empty.
static func build(build_name: String) -> Dictionary:
	return (_load().get("builds", {}) as Dictionary).get(build_name, {})


## `{ok, errors, stats}` for a named build; the rules are in Rust.
static func assemble_named(build_name: String) -> Dictionary:
	var slots := build(build_name)
	if slots.is_empty():
		return {"ok": false, "errors": ["no build named '%s'" % build_name], "stats": {}}
	return WeaponBuild.assemble(catalogue(), slots)


## The visible gun: the receiver at the origin, every other part on the mount its parent
## part provides, one MeshInstance3D per slot named after it. Markers (`Sight`, `Muzzle`)
## come from the outermost part that has them, so a suppressor's muzzle wins over the
## barrel's; that part's `marker_meta` for the marker becomes its meta (a scope's eye
## relief on its `Sight`).
static func build_model(slots: Dictionary) -> Node3D:
	var parts := catalogue()
	var root := Node3D.new()
	root.name = "Gun"
	var placed: Dictionary[String, Transform3D] = {}
	var markers: Dictionary[String, Array] = {}
	var receiver_id := str(slots.get("receiver", ""))
	if not parts.has(receiver_id):
		return root
	# Breadth first from the receiver: each part's mounts place the parts in the slots it
	# provides, one level further out.
	var queue: Array = [["receiver", Transform3D.IDENTITY, 0]]
	while not queue.is_empty():
		var entry: Array = queue.pop_front()
		var slot: String = entry[0]
		var xf: Transform3D = entry[1]
		var depth: int = entry[2]
		var part: Dictionary = parts.get(str(slots.get(slot, "")), {})
		if part.is_empty():
			continue
		placed[slot] = xf
		var inst := MeshInstance3D.new()
		inst.name = slot
		inst.mesh = GunPartMeshes.mesh(str(part.get("mesh", "")))
		inst.transform = xf
		root.add_child(inst)
		var part_markers: Dictionary = part.get("markers", {})
		for marker: String in part_markers:
			var at: Vector3 = xf * _vec(part_markers[marker])
			if not markers.has(marker) or int(markers[marker][1]) < depth:
				markers[marker] = [at, depth, (part.get("marker_meta", {}) as Dictionary).get(marker, {})]
		var mounts: Dictionary = part.get("mounts", {})
		for child_slot: String in part.get("provides", []):
			if slots.has(child_slot) and mounts.has(child_slot) and not placed.has(child_slot):
				queue.append([child_slot, xf * Transform3D(Basis.IDENTITY, _vec(mounts[child_slot])), depth + 1])
	for marker: String in markers:
		var node := Marker3D.new()
		node.name = marker
		node.position = markers[marker][0]
		var meta: Dictionary = markers[marker][2]
		for key: String in meta:
			node.set_meta(StringName(key), meta[key])
		root.add_child(node)
	return root


static func _vec(value: Variant) -> Vector3:
	var a: Array = value if value is Array else [0.0, 0.0, 0.0]
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

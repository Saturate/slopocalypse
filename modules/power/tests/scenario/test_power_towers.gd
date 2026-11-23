extends GdUnitTestSuite
## On the default map every piece of the map's power lines is put up, solid at its feet, with
## wires to its neighbours through the wires module (as many on each span as both its towers
## carry, and no two touching), at the same places on two builds of the map from the same seed.

const MODULE := "res://modules/power/power_module.gd"
const WIRES := "res://modules/wires/wires_module.gd"
const LAYOUT_TEST := "res://modules/power/tests/unit/test_power_layout.gd"


## Stands in for the voxel world: the map's lines and ground, nothing else.
class Ground:
	extends Node
	var shape: MapShape

	func map_power_lines() -> Array[Dictionary]:
		return shape.power_lines()

	func map_power_substation() -> Dictionary:
		return shape.power_substation()

	func ground_height(x: float, z: float) -> float:
		return shape.height_at(x, z)


func after() -> void:
	WorldMaps.clear()


func _ground() -> Ground:
	WorldMaps.clear()
	assert_bool(WorldMaps.select_default()).is_true()
	var ground: Ground = auto_free(Ground.new())
	ground.shape = WorldMaps.shape()
	ground.add_to_group(&"ground")
	add_child(ground)
	return ground


func _module() -> Node:
	var module: Node = auto_free((load(MODULE) as GDScript).new())
	module.set(&"all_at_once", true)
	add_child(module)
	return module


func test_a_server_puts_up_every_tower_with_wires_to_its_neighbours() -> void:
	var ground := _ground()
	var wires: Node = auto_free((load(WIRES) as GDScript).new())
	wires.set(&"visual", false)
	add_child(wires)
	var module := _module()
	EventBus.publish(&"world.ready", {})
	var lines := ground.map_power_lines()
	var layout: Dictionary = module.get(&"layout")
	var towers: Array = module.get(&"towers")
	var planned: Array = layout["towers"]
	assert_int(towers.size()).is_equal(planned.size())
	assert_int(towers.size()).is_greater(20)
	var made := {}
	for piece: VoxPiece in towers:
		made[piece.generator] = int(made.get(piece.generator, 0)) + 1
		# Solid at the feet only: four for a pylon, the pole for a pole, two posts for a gantry.
		var shapes := {"VoxLatticePylon": 4, "VoxPowerPole": 1, "VoxTerminalGantry": 2}
		if shapes.has(piece.generator):
			assert_int(piece.shape_count()).is_equal(shapes[piece.generator])
	assert_int(made.get("VoxSubstation", 0)).is_equal(1)
	assert_int(made.get("VoxLatticePylon", 0)).is_greater(0)
	assert_int(made.get("VoxPowerPole", 0)).is_greater(0)
	assert_int(made.get("VoxTerminalGantry", 0)).is_equal(lines.filter(func(l: Dictionary) -> bool: return l["from"] == "substation").size())
	# Every tower is the end of a wire from each of its attach points, and each line's wires
	# reached the wires module under its own owner.
	var ends := {}
	for i in lines.size():
		var wire_set: Dictionary = (layout["wires"] as Array)[i]
		var spans: Array = wire_set["spans"]
		assert_int(spans.size()).is_greater_equal((lines[i]["points"] as Array).size() - 1)
		assert_int(wires.call(&"span_count", "power/%d" % i)).is_equal(spans.size())
		for p: Array in wire_set["pairs"]:
			var a: Dictionary = planned[int(p[0])]
			var b: Dictionary = planned[int(p[1])]
			assert_int(int(p[2])).is_equal((b["attach"] as Array).size())
			assert_int(int(p[2])).is_equal((a["attach"] as Array).size())
		for s: Dictionary in spans:
			ends[s["from"]] = true
			ends[s["to"]] = true
	var every: Array = (load(LAYOUT_TEST) as GDScript).call(&"all_spans", layout)
	assert_array((load(LAYOUT_TEST) as GDScript).call(&"touching", every, 0.5)).is_empty()
	for t: Dictionary in planned:
		for a: Vector3 in (t["attach"] as Array) + (t["tap"] as Array):
			assert_bool(ends.has(a)).override_failure_message("a %s at %s has a bare arm" % [t["kind"], (t["transform"] as Transform3D).origin]).is_true()


func test_two_builds_put_the_towers_in_the_same_places() -> void:
	var cfg: Dictionary = Data.load_json(PowerLayout.CONFIG)
	var earlier := _ground()
	var first := PowerLayout.plan(earlier.map_power_lines(), earlier.map_power_substation(), cfg, Callable(earlier, &"ground_height"))
	var ground := _ground()
	var again := PowerLayout.plan(ground.map_power_lines(), ground.map_power_substation(), cfg, Callable(ground, &"ground_height"))
	var a: Array = first["towers"]
	var b: Array = again["towers"]
	assert_int(b.size()).is_equal(a.size())
	for i in a.size():
		assert_bool((a[i]["transform"] as Transform3D).is_equal_approx(b[i]["transform"])).override_failure_message("tower %d moved" % i).is_true()
		assert_dict(b[i]["params"]).is_equal(a[i]["params"])

extends GdUnitTestSuite
## Every breakable sample (the range's walls, a house per wall material) takes every hit on the
## impact ladder, each on its own fresh copy, and the rules that must hold whatever the
## numbers are tuned to are checked: a bigger blast never does less, the same hit on the same
## building does the same everywhere, nothing is left standing on nothing, and a hit is
## handled within a frame's budget. The table of what each hit did is printed (and written to
## `$DESTRUCTION_REPORT` when that is set) to read alongside the `ladder` capture.

const MISSIONS := "res://modules/missions/missions_module.gd"
const INVENTORY := "res://modules/inventory/inventory_module.gd"
## Far enough apart that the biggest blast on one copy doesn't reach the next.
const SPACING := 40.0
## Server time one hit may take, milliseconds. A blast into brick takes 300-900 ms today, almost
## all of it `MissionBuilding._crumble_loose` walking every voxel round each knocked-out brick
## in GDScript; this only stops it getting worse until that moves into the voxel kit, then it
## comes down to a frame or two.
const BUDGET_MS := 1500.0
## The hit the determinism copies take.
const SAME_HIT := "charge"

static var _results: Array = []
static var _twins: Array = []
static var _hits: Array[Dictionary] = []
static var _subjects: Array[Dictionary] = []

var _missions: Node
var _inventory: Node


func before() -> void:
	_inventory = (load(INVENTORY) as GDScript).new()
	add_child(_inventory)
	_missions = (load(MISSIONS) as GDScript).new()
	add_child(_missions)
	EventBus.publish(&"world.ready", {"spawn": Vector3.ZERO})


func after() -> void:
	_missions.set(&"buildings", [])
	_missions.call(&"_build_buildings")
	_missions.queue_free()
	_inventory.queue_free()
	_results.clear()
	_twins.clear()


## Builds every copy, hits each once and measures it; once per suite.
func _table() -> void:
	if not _results.is_empty():
		return
	_subjects = ImpactLadder.subjects()
	_hits = ImpactLadder.hits()
	var same := _hits.find(_hits.filter(func(h: Dictionary) -> bool: return str(h["label"]).begins_with(SAME_HIT))[0])
	var entries: Array = []
	for s in _subjects.size():
		for h in _hits.size() + 1:
			entries.append(ImpactLadder.entry(_subjects[s], s, Vector3(h * SPACING, 0.0, s * SPACING)))
	# The missions module builds and owns them, so hits reach them the way they do in a run.
	_missions.set(&"buildings", entries)
	_missions.call(&"_build_buildings")
	await get_tree().physics_frame
	var nodes: Array[MissionBuilding] = _missions.call(&"building_nodes")
	var start: Array[int] = []
	for b in nodes:
		start.append(b.model().voxel_count())
	var ms: Array[float] = []
	for i in nodes.size():
		var h := i % (_hits.size() + 1)
		var t := Time.get_ticks_usec()
		# The extra copy at the end of each row takes the same hit again, for determinism.
		ImpactLadder.apply(nodes[i], _hits[same if h == _hits.size() else h])
		ms.append(float(Time.get_ticks_usec() - t) / 1000.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for s in _subjects.size():
		var row: Array = []
		for h in _hits.size() + 1:
			var i := s * (_hits.size() + 1) + h
			var m := _measure(nodes[i], start[i], ms[i])
			if h < _hits.size():
				row.append(m)
			else:
				_twins.append([row[same], m])
		_results.append(row)
	_report()
	# Pieces that fell land (and crush) after a delay; let that happen while their buildings
	# still exist, or the later suites see the timers fire on freed ones.
	await get_tree().create_timer(float((_missions.get(&"config") as Dictionary)["buildings"].get("fall_seconds", 0.6)) + 0.5).timeout


func _measure(b: MissionBuilding, start: int, ms: float) -> Dictionary:
	var broken: Array[int] = []
	for id in b.segment_count():
		if b.is_broken(id):
			broken.append(id)
	var panes: Array[int] = []
	for p in b.pane_count():
		if b.is_pane_broken(p):
			panes.append(p)
	var none: Array[int] = []
	return {
		"start": start,
		"left": b.model().voxel_count(),
		"removed": start - b.model().voxel_count(),
		"broken": broken,
		"pieces": b.segment_count(),
		"panes": panes,
		"open": ImpactLadder.openness(b),
		"ms": ms,
		"unsupported": b.server_unsupported(none),
		"overloaded": b.server_overloaded(none),
	}


func _report() -> void:
	var lines: Array[String] = []
	lines.append("Destruction table: each cell is open share of the 2 m patch at the aim point / voxels removed / pieces broken of all / panes broken.")
	lines.append("")
	var head := "| subject |"
	var rule := "| --- |"
	for h in _hits:
		head += " %s |" % h["label"]
		rule += " --- |"
	lines.append(head)
	lines.append(rule)
	for s in _subjects.size():
		var line := "| %s |" % _subjects[s].get("label", _subjects[s].get("material"))
		for m: Dictionary in _results[s]:
			line += " %d%% / %d / %d of %d / %d |" % [roundi(float(m["open"]) * 100.0), int(m["removed"]), (m["broken"] as Array).size(), int(m["pieces"]), (m["panes"] as Array).size()]
		lines.append(line)
	lines.append("")
	var slowest := 0.0
	var slowest_at := ""
	for s in _subjects.size():
		for h in _hits.size():
			var ms := float(_results[s][h]["ms"])
			if ms > slowest:
				slowest = ms
				slowest_at = "%s, %s" % [_subjects[s].get("label", ""), _hits[h]["label"]]
	lines.append("Slowest hit: %.1f ms (%s)" % [slowest, slowest_at])
	var text := "\n".join(lines)
	print(text)
	var path := OS.get_environment("DESTRUCTION_REPORT")
	if not path.is_empty():
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(text + "\n")


func _name(s: int) -> String:
	return str(_subjects[s].get("label", _subjects[s].get("material")))


func test_every_subject_takes_every_hit() -> void:
	await _table()
	assert_int(_results.size()).is_equal(_subjects.size())
	for row: Array in _results:
		assert_int(row.size()).is_equal(_hits.size())


func test_a_bigger_blast_never_does_less() -> void:
	await _table()
	for s in _subjects.size():
		var last := {}
		var last_label := ""
		for h in _hits.size():
			if str(_hits[h]["kind"]) != "blast":
				continue
			var m: Dictionary = _results[s][h]
			if not last.is_empty():
				var why := "%s: %s did less than %s" % [_name(s), _hits[h]["label"], last_label]
				assert_int(int(m["removed"])).override_failure_message(why + " (voxels)").is_greater_equal(int(last["removed"]))
				assert_float(float(m["open"])).override_failure_message(why + " (open)").is_greater_equal(float(last["open"]) - 0.001)
				assert_int((m["broken"] as Array).size()).override_failure_message(why + " (pieces)").is_greater_equal((last["broken"] as Array).size())
			last = m
			last_label = str(_hits[h]["label"])


func test_more_rounds_in_one_spot_never_do_less() -> void:
	await _table()
	for s in _subjects.size():
		var one: Dictionary = _results[s][0]
		var ten: Dictionary = _results[s][1]
		assert_int(int(ten["removed"])).override_failure_message(_name(s)).is_greater_equal(int(one["removed"]))


func test_the_same_hit_does_the_same_on_another_copy() -> void:
	await _table()
	for s in _twins.size():
		var a: Dictionary = _twins[s][0]
		var b: Dictionary = _twins[s][1]
		assert_int(int(b["left"])).override_failure_message(_name(s)).is_equal(int(a["left"]))
		assert_array(b["broken"]).override_failure_message(_name(s)).is_equal(a["broken"])
		assert_array(b["panes"]).override_failure_message(_name(s)).is_equal(a["panes"])


func test_nothing_is_left_standing_on_nothing() -> void:
	await _table()
	for s in _subjects.size():
		for h in _hits.size():
			var m: Dictionary = _results[s][h]
			var at := "%s, %s" % [_name(s), _hits[h]["label"]]
			assert_array(m["unsupported"]).override_failure_message(at + ": unsupported").is_empty()
			assert_array(m["overloaded"]).override_failure_message(at + ": overloaded").is_empty()


func test_every_hit_is_handled_within_budget() -> void:
	await _table()
	for s in _subjects.size():
		for h in _hits.size():
			assert_float(float(_results[s][h]["ms"])).override_failure_message("%s, %s" % [_name(s), _hits[h]["label"]]).is_less(BUDGET_MS)

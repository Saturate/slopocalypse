class_name ApartmentRooms
extends RefCounted
## The rooms of one flat in a `VoxApartment` and the furniture in them.
##
## A flat is three strips across the block: rooms on the street side, a hall down the middle
## and rooms on the courtyard side. The street-side room next to the stairwell is the kitchen
## (the flat's front door opens into it, along the stairwell wall); the courtyard-side room
## next to the stairwell is the living room (with the balcony door); the bathroom closes off
## the far end of the hall, or takes the smallest bedroom when the hall needs all its length;
## every other room is a bedroom. Room walls only ever fall between
## two windows and no room is narrower than `MIN_ROOM`, so how many rooms a flat has depends
## on its width, its windows and its seed: one window makes a studio, a wide flat with three
## can have four bedrooms.
##
## Doors keep a clear strip either side, and the path from the front door to the hall stays
## open, so furniture never blocks a way through (tests check this in the built model).

const HALL := 1.1
const DOOR := Vector2(0.9, 2.1)
const LIVING_DOOR := 1.6
const BATH_DOOR := 0.9
const BATH_LENGTH := Vector2(1.4, 2.0)
const SMALL_BATH := 1.0
## Furniture keeps this far from either side of a doorway.
const DOOR_CLEAR := 1.0
## Floor kept free in front of cupboards, shelves, the fridge and the counter, to reach them.
const REACH := 0.6
const BATH_CLEAR := 0.5
## How far a piece may reach past its footprint (about half a voxel at the usual 0.15 m).
const SPILL := 0.08
## Spacing of the places tried along a wall.
const SPOT_STEP := 0.1
## Width of the strip kept open along the stairwell wall from the front door to the hall.
const ENTRY_STRIP := 1.0
const FRONT_SHARE := 0.38
const FRONT_DEPTH := Vector2(2.6, 4.2)
## Narrowest a room may be, wall to wall, so there is room to move and fight in it.
const MIN_ROOM := 2.25
## The living room needs a sofa facing a TV across it.
const MIN_LIVING := 2.7

const PLASTER := Color(0.92, 0.9, 0.86)
const OAK_FLOOR := Color(0.74, 0.58, 0.4)
const KITCHEN_FLOOR := Color(0.58, 0.58, 0.56)
const TILE := Color(0.86, 0.88, 0.89)
const RUGS := [Color(0.55, 0.22, 0.18), Color(0.82, 0.78, 0.68), Color(0.3, 0.36, 0.45), Color(0.45, 0.5, 0.38)]
const WORKTOPS := [VoxFurniture.OAK, Color(0.25, 0.25, 0.26), Color(0.85, 0.85, 0.83)]

const FACINGS: Array[Vector3] = [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]


## The plan of a flat, in model x and z (y comes from each storey's level):
## `rooms` ({kind, rect, first} with kind kitchen, living, bedroom, bath or hall), `walls`
## (partition footprints), `doors` ({rect, across}: openings; `across` is the axis people walk
## through them along, 0 for x, 1 for z), `clear` (floor kept free of furniture), `entry`
## (the way from the front door to the hall) and `bedrooms`.
## `inner` is the flat's floor inside its walls, `stair_high` whether the stairwell is on its
## +X side, `windows` the x of its windows (the same on both sides), `extra_clear` floor
## to keep free (balcony doors) and `tall_avoid` floor in front of windows.
static func plan_flat(inner: Rect2, stair_high: bool, windows: Array[float], seed: int, v: float, extra_clear: Array[Rect2], tall_avoid: Array[Rect2]) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var c := windows.size()
	# Windows from the stairwell outwards.
	var order: Array[float] = windows.duplicate()
	order.sort()
	if stair_high:
		order.reverse()
	var t := maxf(v, 0.12)
	var start := inner.end.x if stair_high else inner.position.x
	var far := inner.position.x if stair_high else inner.end.x
	var dir := -1.0 if stair_high else 1.0
	# As many rooms a side as stay wide enough (the living room wider than the rest).
	var most_front := 1
	while most_front < c and _best_groups(order, most_front + 1, start, far, dir, t, MIN_ROOM).size() > 0:
		most_front += 1
	var most_back := 1
	while most_back < c and _best_groups(order, most_back + 1, start, far, dir, t, MIN_LIVING).size() > 0:
		most_back += 1
	var n_front := rng.randi_range(1, most_front)
	var n_back := rng.randi_range(1, most_back)
	if n_front + n_back == 2:
		if most_front > 1 and (most_back == 1 or rng.randf() < 0.5):
			n_front = 2
		elif most_back > 1:
			n_back = 2
	var plan := _plan(inner, stair_high, order, n_front, n_back, v, extra_clear, tall_avoid)
	# A flat whose only bedroom had to become the bathroom gets another room.
	while int(plan["bedrooms"]) == 0 and (n_front < most_front or n_back < most_back):
		if n_front < most_front:
			n_front += 1
		else:
			n_back += 1
		plan = _plan(inner, stair_high, order, n_front, n_back, v, extra_clear, tall_avoid)
	return plan


static func _plan(inner: Rect2, stair_high: bool, order: Array[float], n_front: int, n_back: int, v: float, extra_clear: Array[Rect2], tall_avoid: Array[Rect2]) -> Dictionary:
	var c := order.size()
	var t := maxf(v, 0.12)
	var x0 := inner.position.x
	var x1 := inner.end.x
	var z0 := inner.position.y
	var z1 := inner.end.y
	var zs := z0 + clampf(inner.size.y * FRONT_SHARE, FRONT_DEPTH.x, FRONT_DEPTH.y)
	var hall0 := zs + t
	var hall1 := hall0 + HALL
	var back0 := hall1 + t
	var dir_x := -1.0 if stair_high else 1.0
	var front_groups := _best_groups(order, n_front, x1 if stair_high else x0, x0 if stair_high else x1, dir_x, t, MIN_ROOM)
	var back_groups := _best_groups(order, n_back, x1 if stair_high else x0, x0 if stair_high else x1, dir_x, t, MIN_LIVING)
	if front_groups.is_empty():
		front_groups = [c]
	if back_groups.is_empty():
		back_groups = [c]
	var walls: Array[Rect2] = []
	var doors: Array[Dictionary] = []
	var rooms: Array[Dictionary] = []
	var clear: Array[Rect2] = []
	walls.append(Rect2(x0, zs, x1 - x0, t))
	walls.append(Rect2(x0, hall1, x1 - x0, t))
	var dir := -1.0 if stair_high else 1.0
	var start := x1 if stair_high else x0
	var far := x0 if stair_high else x1
	var front := _strip(order, front_groups, start, far, dir, t)
	var back := _strip(order, back_groups, start, far, dir, t)
	# How far from the stairwell the hall has to run to reach every room's door.
	var reach := 0.0
	for i in front.size():
		var span: Vector2 = front[i]
		var rect := _span_rect(span, z0, zs)
		rooms.append({"kind": "kitchen" if i == 0 else "bedroom", "rect": rect})
		# The door to the hall sits at the room's stairwell end.
		var door := _span_rect(Vector2(span.x + dir * 0.15, span.x + dir * (0.15 + DOOR.x)), zs - v, hall0 + v)
		doors.append({"rect": door, "across": 1})
		reach = maxf(reach, absf(span.x - start) + 0.25 + DOOR.x)
		if i > 0:
			walls.append(_span_rect(Vector2(span.x - dir * t, span.x), z0, zs))
	for i in back.size():
		var span: Vector2 = back[i]
		var rect := _span_rect(span, back0, z1)
		rooms.append({"kind": "living" if i == 0 else "bedroom", "rect": rect})
		var width := maxf(DOOR.x, minf(LIVING_DOOR, absf(span.y - span.x) - 0.6)) if i == 0 else DOOR.x
		var from := span.x + dir * (0.3 if i == 0 else 0.15)
		doors.append({"rect": _span_rect(Vector2(from, from + dir * width), hall1 - v, back0 + v), "across": 1})
		reach = maxf(reach, absf(from - start) + width + 0.1)
		if i > 0:
			walls.append(_span_rect(Vector2(span.x - dir * t, span.x), back0, z1))
	# The bathroom closes off the far end of the hall when the hall can spare it; otherwise
	# the smallest bedroom is the bathroom (one with a window).
	var bath_len := minf(BATH_LENGTH.y, absf(far - start) - reach - t)
	var hall_end := far
	var smallest := -1
	var bedroom_count := 0
	for i in rooms.size():
		if rooms[i]["kind"] == "bedroom":
			bedroom_count += 1
		if rooms[i]["kind"] == "bedroom" and (smallest < 0 or (rooms[i]["rect"] as Rect2).get_area() < (rooms[smallest]["rect"] as Rect2).get_area()):
			smallest = i
	# A flat's only bedroom stays a bedroom while a small bathroom still fits at the end.
	if bath_len >= BATH_LENGTH.x or smallest < 0 or (bedroom_count == 1 and bath_len >= SMALL_BATH):
		bath_len = maxf(bath_len, SMALL_BATH)
		hall_end = far - dir * (bath_len + t)
		rooms.append({"kind": "bath", "rect": _span_rect(Vector2(far, far - dir * bath_len), hall0, hall1)})
		var bath_wall := _span_rect(Vector2(far - dir * bath_len, hall_end), hall0, hall1)
		walls.append(bath_wall)
		var mid := (hall0 + hall1) / 2.0
		doors.append({"rect": Rect2(bath_wall.position.x - v, mid - BATH_DOOR / 2.0, bath_wall.size.x + v * 2.0, BATH_DOOR), "across": 0})
	else:
		rooms[smallest]["kind"] = "bath"
	rooms.append({"kind": "hall", "rect": _span_rect(Vector2(start, hall_end), hall0, hall1)})
	var bedrooms := 0
	for room in rooms:
		room["first"] = room["kind"] == "bedroom" and bedrooms == 0
		if room["kind"] == "bedroom":
			bedrooms += 1
	for door: Dictionary in doors:
		var r: Rect2 = door["rect"]
		if int(door["across"]) == 1:
			clear.append(Rect2(r.position.x - 0.1, r.position.y - DOOR_CLEAR, r.size.x + 0.2, r.size.y + DOOR_CLEAR * 2.0))
		else:
			# The bathroom is small: its door keeps less clear.
			clear.append(Rect2(r.position.x - BATH_CLEAR, r.position.y - 0.1, r.size.x + BATH_CLEAR * 2.0, r.size.y + 0.2))
	# From the front door (in the stairwell wall, near the street) along that wall to the hall.
	var entry := _span_rect(Vector2(start, start + dir * ENTRY_STRIP), z0, zs)
	clear.append(entry)
	clear.append_array(extra_clear)
	return {"rooms": rooms, "walls": walls, "doors": doors, "clear": clear, "tall_avoid": tall_avoid, "bedrooms": bedrooms, "entry": entry}


## How many windows each of `n` rooms in a row gets (from the stairwell out) so the
## narrowest room is as wide as it can be, ties going to a bigger first room (the kitchen or
## living room); empty if every way leaves a room narrower than MIN_ROOM, or the first one
## narrower than `first_min`.
static func _best_groups(order: Array[float], n: int, start: float, far: float, dir: float, t: float, first_min: float) -> Array[int]:
	var best: Array[int] = []
	var best_width := MIN_ROOM - 0.001
	for groups in _compositions(order.size(), n):
		var spans := _strip(order, groups, start, far, dir, t)
		if absf(spans[0].y - spans[0].x) < first_min:
			continue
		var narrowest := INF
		for span in spans:
			narrowest = minf(narrowest, absf(span.y - span.x))
		if narrowest > best_width + 0.001 or (absf(narrowest - best_width) <= 0.001 and not best.is_empty() and groups[0] > best[0]):
			best = groups
			best_width = narrowest
	return best


## Every way to write `total` as `n` whole numbers of at least one, in order.
static func _compositions(total: int, n: int) -> Array[Array]:
	var out: Array[Array] = []
	if n == 1:
		out.append([total] as Array[int])
		return out
	for first in range(1, total - n + 2):
		for rest in _compositions(total - first, n - 1):
			var groups: Array[int] = [first]
			groups.append_array(rest)
			out.append(groups)
	return out


## Room spans along x from the stairwell end outwards (as Vector2 from, to in walking order),
## each holding the next `groups[i]` windows, with a partition between neighbours.
static func _strip(order: Array[float], groups: Array[int], start: float, far: float, dir: float, t: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var at := start
	var used := 0
	for i in groups.size():
		used += groups[i]
		var end := far
		if i < groups.size() - 1:
			end = (order[used - 1] + order[used]) / 2.0 - dir * t / 2.0
		out.append(Vector2(at, end))
		at = end + dir * t
	return out


static func _span_rect(span: Vector2, z0: float, z1: float) -> Rect2:
	return Rect2(minf(span.x, span.y), z0, absf(span.y - span.x), z1 - z0)


## Partitions, doorways and wall and floor finishes for one storey of a flat whose floor
## inside its walls is `inner`; without `partitions`, the flat is one plastered room.
static func build_rooms(m: VoxelModel, plan: Dictionary, inner: Rect2, level: float, ceiling: float, partitions: bool) -> void:
	var v := m.voxel_size()
	if not partitions:
		var g := inner.grow(v)
		m.paint_box(Vector3(g.position.x, level, g.position.y), Vector3(g.end.x, ceiling + v, g.end.y), PLASTER, 0.02, 0)
		m.paint_box(Vector3(inner.position.x, level - v, inner.position.y), Vector3(inner.end.x, level, inner.end.y), OAK_FLOOR, 0.1, 1)
		return
	for w: Rect2 in plan["walls"]:
		m.fill_box(Vector3(w.position.x, level, w.position.y), Vector3(w.end.x, ceiling, w.end.y), PLASTER, 0.02, 0)
	for door: Dictionary in plan["doors"]:
		var r: Rect2 = door["rect"]
		m.carve_box(Vector3(r.position.x, level, r.position.y), Vector3(r.end.x, level + DOOR.y, r.end.y))
	for room: Dictionary in plan["rooms"]:
		var r: Rect2 = room["rect"]
		var grown := r.grow(v)
		m.paint_box(Vector3(grown.position.x, level, grown.position.y), Vector3(grown.end.x, ceiling + v, grown.end.y), PLASTER, 0.02, 0)
		var floor := OAK_FLOOR
		match room["kind"]:
			"kitchen":
				floor = KITCHEN_FLOOR
			"bath":
				floor = TILE
		m.paint_box(Vector3(r.position.x, level - v, r.position.y), Vector3(r.end.x, level, r.end.y), floor, 0.1, 1)


## Furniture for one storey of a flat, by room.
static func furnish(m: VoxelModel, plan: Dictionary, level: float, ceiling: float, rng: RandomNumberGenerator) -> void:
	var fabric: Color = VoxFurniture.FABRICS[rng.randi() % VoxFurniture.FABRICS.size()]
	var wood: Color = VoxFurniture.OAK if rng.randf() < 0.6 else VoxFurniture.TEAK
	for room: Dictionary in plan["rooms"]:
		# Floor furniture keeps off (`taken`), the same plus window fronts for tall pieces
		# (`tall`), and only what is already standing (`solid`).
		var taken: Array[Rect2] = (plan["clear"] as Array[Rect2]).duplicate()
		var tall: Array[Rect2] = taken.duplicate()
		tall.append_array(plan["tall_avoid"])
		var solid: Array[Rect2] = []
		var lists: Array = [taken, tall, solid]
		var r: Rect2 = room["rect"]
		match room["kind"]:
			"living":
				_living(m, r, level, ceiling, lists, rng, fabric, wood)
			"kitchen":
				_kitchen(m, r, level, ceiling, lists, rng, wood)
			"bedroom":
				_bedroom(m, r, level, lists, rng, bool(room["first"]), wood)
			"bath":
				_bath(m, r, level, lists)


static func _living(m: VoxelModel, r: Rect2, level: float, ceiling: float, lists: Array, rng: RandomNumberGenerator, fabric: Color, wood: Color) -> void:
	var taken: Array[Rect2] = lists[0]
	var tall: Array[Rect2] = lists[1]
	# Sofa on one wall, the TV facing it on the opposite one, a coffee table between them.
	var pairs: Array[Vector2i] = [Vector2i(2, 3), Vector2i(3, 2), Vector2i(0, 1), Vector2i(1, 0)]
	_shuffle(pairs, rng)
	var seated := false
	for pair in pairs:
		if seated:
			break
		var span := r.size.x if pair.x >= 2 else r.size.y
		if span < 2.6 or span > 6.0:
			continue
		for spot in _wall_spots(r, VoxFurniture.SOFA, pair.x, rng, true):
			var across: Vector3 = spot["facing"]
			var at: Vector3 = spot["at"]
			var depth := span - VoxFurniture.TV_BENCH.y / 2.0 - VoxFurniture.SOFA.y / 2.0
			var tv_at := at + across * depth
			var tv_rect := _rect(tv_at, VoxFurniture.TV_BENCH, -across)
			var table_at := at + across * (VoxFurniture.SOFA.y / 2.0 + 0.4 + VoxFurniture.COFFEE_TABLE.y / 2.0)
			var view := _rect(at + across * (depth / 2.0), Vector2(VoxFurniture.SOFA.x, depth), across)
			var table_rect := _rect(table_at, VoxFurniture.COFFEE_TABLE, across)
			# A way through may cross between the sofa and the TV; furniture may not.
			if not _free(spot["rect"], taken) or not _free(tv_rect, tall) or not _free(table_rect, taken) or not _free(view, lists[2]):
				continue
			VoxFurniture.sofa(m, _lift(at, level), across, fabric)
			VoxFurniture.tv(m, _lift(tv_at, level), -across, wood)
			VoxFurniture.coffee_table(m, _lift(table_at, level), across)
			var rug := _rect(table_at, Vector2(2.0, 1.4), across)
			m.paint_box(Vector3(rug.position.x, level - m.voxel_size(), rug.position.y), Vector3(rug.end.x, level, rug.end.y), RUGS[rng.randi() % RUGS.size()], 0.08, 3)
			_take(view, lists)
			var right := Vector3(across.z, 0.0, -across.x)
			for side: float in [1.0, -1.0]:
				var lamp := at + right * side * (VoxFurniture.SOFA.x / 2.0 + 0.3)
				if r.encloses(_rect(lamp, VoxFurniture.FLOOR_LAMP, across)) and _free(_rect(lamp, VoxFurniture.FLOOR_LAMP, across), tall):
					VoxFurniture.floor_lamp(m, _lift(lamp, level))
					_take(_rect(lamp, VoxFurniture.FLOOR_LAMP, across), lists)
					break
			seated = true
			break
	# A dining table with chairs and a pendant over it, where there is room.
	var ends := r.get_area() > 22.0
	var size := VoxFurniture.DINING_TABLE if r.get_area() > 14.0 else VoxFurniture.KITCHEN_TABLE
	var dining = _floor_spot(r, VoxFurniture.dining_extent(size, ends), taken, rng)
	if dining != null:
		var at: Vector3 = dining["at"]
		VoxFurniture.table_with_chairs(m, _lift(at, level), dining["facing"], size, wood, ends)
		VoxFurniture.pendant(m, _lift(at, level), ceiling - level, rng.randf() < 0.4)
		_take(_rect(at, VoxFurniture.dining_extent(size, ends), dining["facing"]), lists)
	for spot in _reach_spots(r, VoxFurniture.BOOKSHELF, rng, lists, true):
		VoxFurniture.bookshelf(m, _lift(spot["at"], level), spot["facing"], rng)
		_take_reach(spot, lists)
	for spot in _first_spots(r, VoxFurniture.PLANT, rng, tall):
		VoxFurniture.plant(m, _lift(spot["at"], level))
		_take(spot["rect"], lists)


static func _kitchen(m: VoxelModel, r: Rect2, level: float, ceiling: float, lists: Array, rng: RandomNumberGenerator, wood: Color) -> void:
	var tall: Array[Rect2] = lists[1]
	var worktop: Color = WORKTOPS[rng.randi() % WORKTOPS.size()]
	var length := 2.7
	var placed := false
	while length >= 0.9 and not placed:
		for spot in _reach_spots(r, Vector2(length, VoxFurniture.COUNTER_DEPTH), rng, lists, false):
			# Wall cupboards only where they don't cover a window.
			var upper := _free(spot["rect"], tall)
			VoxFurniture.counter(m, _lift(spot["at"], level), spot["facing"], length, worktop, upper)
			_take_reach(spot, lists)
			placed = true
		length -= 0.3
	for spot in _reach_spots(r, VoxFurniture.FRIDGE, rng, lists, true):
		VoxFurniture.fridge(m, _lift(spot["at"], level), spot["facing"])
		_take_reach(spot, lists)
	var table = _floor_spot(r, VoxFurniture.dining_extent(VoxFurniture.KITCHEN_TABLE, false), lists[0], rng)
	if table != null:
		VoxFurniture.table_with_chairs(m, _lift(table["at"], level), table["facing"], VoxFurniture.KITCHEN_TABLE, wood, false)
		VoxFurniture.pendant(m, _lift(table["at"], level), ceiling - level, false)


static func _bedroom(m: VoxelModel, r: Rect2, level: float, lists: Array, rng: RandomNumberGenerator, first: bool, wood: Color) -> void:
	var taken: Array[Rect2] = lists[0]
	var double := first and minf(r.size.x, r.size.y) >= 2.5
	var bed := VoxFurniture.DOUBLE_BED if double else VoxFurniture.SINGLE_BED
	var stands := 2 if double else 1
	# The bed and its nightstands as one block against a wall.
	var block := Vector2(bed.x + VoxFurniture.NIGHTSTAND.x * stands + 0.1, bed.y)
	var duvet: Color = VoxFurniture.FABRICS[rng.randi() % VoxFurniture.FABRICS.size()].lightened(0.25)
	var sides: Array[int] = [0, 1, 2, 3]
	_shuffle(sides, rng)
	var done := false
	for side in sides:
		for spot in _wall_spots(r, block, side, rng, true):
			if not _free(spot["rect"], taken):
				continue
			var facing: Vector3 = spot["facing"]
			var right := Vector3(facing.z, 0.0, -facing.x)
			var at: Vector3 = spot["at"]
			var bed_at := at if stands == 2 else at - right * (VoxFurniture.NIGHTSTAND.x + 0.1) / 2.0
			VoxFurniture.bed(m, _lift(bed_at, level), facing, bed, wood, duvet)
			for s: float in ([-1.0, 1.0] if stands == 2 else [1.0]):
				var stand := bed_at + right * s * (bed.x / 2.0 + VoxFurniture.NIGHTSTAND.x / 2.0 + 0.05) - facing * (bed.y / 2.0 - VoxFurniture.NIGHTSTAND.y / 2.0)
				VoxFurniture.nightstand(m, _lift(stand, level), facing, wood)
			_take(spot["rect"], lists)
			done = true
			break
		if done:
			break
	for spot in _reach_spots(r, VoxFurniture.WARDROBE, rng, lists, true):
		VoxFurniture.wardrobe(m, _lift(spot["at"], level), spot["facing"], VoxFurniture.WHITE if rng.randf() < 0.5 else wood)
		_take_reach(spot, lists)
	if not double:
		# A desk, with its chair in the reach in front of it.
		for spot in _reach_spots(r, VoxFurniture.DESK, rng, lists, false):
			VoxFurniture.desk(m, _lift(spot["at"], level), spot["facing"], wood)
			_take(spot["rect"].merge(spot["front"]), lists)


static func _bath(m: VoxelModel, r: Rect2, level: float, lists: Array) -> void:
	var taken: Array[Rect2] = lists[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for item: Array in [[VoxFurniture.SHOWER, "shower"], [VoxFurniture.TOILET, "toilet"], [VoxFurniture.BASIN, "basin"]]:
		for spot in _first_spots(r, item[0], rng, taken):
			var at := _lift(spot["at"], level)
			match item[1]:
				"shower":
					VoxFurniture.shower(m, at, spot["facing"])
				"toilet":
					VoxFurniture.toilet(m, at, spot["facing"])
				_:
					VoxFurniture.basin(m, at, spot["facing"])
			_take(spot["rect"], lists)


## Every place along wall `side` of `r` where a piece of footprint `size` stands with its back
## to that wall, nearest the middle first when `centred`, else in a random order. Each is
## `{at, facing, rect}` with `at` on the floor (y 0).
static func _wall_spots(r: Rect2, size: Vector2, side: int, rng: RandomNumberGenerator, centred: bool) -> Array[Dictionary]:
	var facing := FACINGS[side]
	var ext := VoxFurniture.extent(size, facing)
	if ext.x > r.size.x + 0.001 or ext.y > r.size.y + 0.001:
		return []
	var along_x := side < 2
	var lo := (r.position.x if along_x else r.position.y) + (ext.x if along_x else ext.y) / 2.0
	var hi := (r.end.x if along_x else r.end.y) - (ext.x if along_x else ext.y) / 2.0
	var fixed := 0.0
	match side:
		0:
			fixed = r.position.y + ext.y / 2.0
		1:
			fixed = r.end.y - ext.y / 2.0
		2:
			fixed = r.position.x + ext.x / 2.0
		_:
			fixed = r.end.x - ext.x / 2.0
	var ts: Array[float] = []
	var t := lo
	while t <= hi + 0.001:
		ts.append(t)
		t += SPOT_STEP
	if centred:
		var mid := (lo + hi) / 2.0
		ts.sort_custom(func(a: float, b: float) -> bool: return absf(a - mid) < absf(b - mid))
	else:
		_shuffle(ts, rng)
	var out: Array[Dictionary] = []
	for at in ts:
		var p := Vector3(at, 0.0, fixed) if along_x else Vector3(fixed, 0.0, at)
		out.append({"at": p, "facing": facing, "rect": Rect2(p.x - ext.x / 2.0, p.z - ext.y / 2.0, ext.x, ext.y)})
	return out


## The first wall spot (as a one-item list, or empty) for a piece of footprint `size` that
## needs `REACH` free in front of it: its body clear of everything kept free (`lists[1]` for
## `tall` pieces, else `lists[0]`), the floor in front clear of anything standing (it may be
## part of a path). Each spot is `{at, facing, rect, front}`.
static func _reach_spots(r: Rect2, size: Vector2, rng: RandomNumberGenerator, lists: Array, tall: bool) -> Array[Dictionary]:
	var avoid: Array[Rect2] = lists[1] if tall else lists[0]
	var sides: Array[int] = [0, 1, 2, 3]
	_shuffle(sides, rng)
	for side in sides:
		for spot in _wall_spots(r, Vector2(size.x, size.y + REACH), side, rng, false):
			var facing: Vector3 = spot["facing"]
			var at: Vector3 = spot["at"] - facing * REACH / 2.0
			var body := _rect(at, size, facing)
			var front := _rect(at + facing * (size.y + REACH) / 2.0, Vector2(size.x, REACH), facing)
			if _free(body, avoid) and _free(front, lists[2]):
				return [{"at": at, "facing": facing, "rect": body, "front": front}]
	return []


static func _take_reach(spot: Dictionary, lists: Array) -> void:
	_take(spot["rect"], lists)
	(lists[0] as Array[Rect2]).append(spot["front"])
	(lists[1] as Array[Rect2]).append(spot["front"])


## The first free wall spot for `size` on any wall, tried in a random order; empty if none.
static func _first_spots(r: Rect2, size: Vector2, rng: RandomNumberGenerator, avoid: Array[Rect2]) -> Array[Dictionary]:
	var sides: Array[int] = [0, 1, 2, 3]
	_shuffle(sides, rng)
	for side in sides:
		for spot in _wall_spots(r, size, side, rng, false):
			if _free(spot["rect"], avoid):
				return [spot]
	return []


## A free place out in the floor for a footprint `ext` (across, along its facing), as
## `{at, facing}`, or null.
static func _floor_spot(r: Rect2, ext: Vector2, taken: Array[Rect2], rng: RandomNumberGenerator) -> Variant:
	var facings: Array[Vector3] = [Vector3(0, 0, 1), Vector3(1, 0, 0)]
	_shuffle(facings, rng)
	var best: Variant = null
	var best_score := -1.0
	for facing in facings:
		var e := VoxFurniture.extent(ext, facing)
		var x := r.position.x + e.x / 2.0 + 0.3
		while x <= r.end.x - e.x / 2.0 - 0.3:
			var z := r.position.y + e.y / 2.0 + 0.3
			while z <= r.end.y - e.y / 2.0 - 0.3:
				var rect := Rect2(x - e.x / 2.0, z - e.y / 2.0, e.x, e.y)
				if _free(rect, taken):
					# Prefer the middle of the free floor: furthest from anything taken.
					var score := _distance_to(rect, taken, r)
					if score > best_score:
						best_score = score
						best = {"at": Vector3(x, 0.0, z), "facing": facing}
				z += 0.3
			x += 0.3
	return best


static func _distance_to(rect: Rect2, taken: Array[Rect2], room: Rect2) -> float:
	var c := rect.get_center()
	var d := minf(minf(c.x - room.position.x, room.end.x - c.x), minf(c.y - room.position.y, room.end.y - c.y))
	for t in taken:
		var cx := clampf(c.x, t.position.x, t.end.x)
		var cz := clampf(c.y, t.position.y, t.end.y)
		d = minf(d, Vector2(cx, cz).distance_to(c))
	return d


static func _free(rect: Rect2, taken: Array[Rect2]) -> bool:
	# Thin parts widen to a whole voxel and may stick out up to half of one.
	var inner := rect.grow(SPILL)
	for t in taken:
		if inner.intersects(t):
			return false
	return true


## Something now stands on `rect`: everything else keeps off it.
static func _take(rect: Rect2, lists: Array) -> void:
	for list: Array[Rect2] in lists:
		list.append(rect)


static func _rect(at: Vector3, size: Vector2, facing: Vector3) -> Rect2:
	var e := VoxFurniture.extent(size, facing)
	return Rect2(at.x - e.x / 2.0, at.z - e.y / 2.0, e.x, e.y)


static func _lift(at: Vector3, level: float) -> Vector3:
	return Vector3(at.x, level, at.z)


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp

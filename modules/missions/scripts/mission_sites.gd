class_name MissionSites
extends RefCounted
## Which of the map's sites a mission goes to, and the place it makes there: the zone's
## centre and footprint, the way its track leaves, and the drop-off where the track meets the
## road network. Pure: the same sites, camp and seed give the same picks on every machine.
##
## A site is an entry of VoxelWorld.map_site_list. A mission template names the kinds it may
## use in `sites` (a site kind, `any` for every kind, `roadside` for a spot beside the
## highway); a template without `sites` is roadside only.

const ROADSIDE := "roadside"
const ANY := "any"
## `pick` results that are not a site's index.
const ROADSIDE_SPOT := -1
const NOWHERE := -2


## Metres from `home` to the site's centre, as the crow flies. The ride out is a fade, not a
## drive, so the way by road is never felt; how far the place lies from the camp is.
static func distance(site: Dictionary, home: Vector3) -> float:
	var c: Vector3 = site["centre"]
	return Vector2(c.x - home.x, c.z - home.z).length()


## The site `template` goes to: a random one (from `rng`) of its kinds, not in `used`, whose
## distance from `home` falls in the template's `distance` range. With none, ROADSIDE_SPOT
## when the template allows the roadside or the map has no sites at all (the flat test
## world), else NOWHERE (the template is not offered this time).
static func pick(template: Dictionary, sites: Array, home: Vector3, used: Dictionary, rng: RandomNumberGenerator) -> int:
	var kinds: Array = template.get("sites", [ROADSIDE])
	if sites.is_empty():
		return ROADSIDE_SPOT
	var span: Array = template.get("distance", [0.0, INF])
	var fits: Array[int] = []
	for i in sites.size():
		var site: Dictionary = sites[i]
		if used.has(i) or not (kinds.has(ANY) or kinds.has(str(site["kind"]))):
			continue
		var d := distance(site, home)
		if d >= float(span[0]) and d <= float(span[1]):
			fits.append(i)
	if not fits.is_empty():
		return fits[rng.randi_range(0, fits.size() - 1)]
	return ROADSIDE_SPOT if kinds.has(ROADSIDE) else NOWHERE


## How far a zone at a place with `foot` reaches from its middle: past the footprint's
## corners by `cfg.zone.radius` metres.
static func zone_radius(foot: Rect2, cfg: Dictionary) -> float:
	return foot.size.length() / 2.0 + float((cfg.get("zone", {}) as Dictionary).get("radius", 30.0))


## What an offer keeps of site `index`, the drop-off worked out (see `_dropoff`): enough to
## lay the zone out and set the group down without the map (clients take the offer from the
## server). `cfg` is the whole missions.json.
static func describe(site: Dictionary, index: int, cfg: Dictionary) -> Dictionary:
	var out := {"index": index, "kind": str(site["kind"]), "centre": site["centre"], "footprint": site["footprint"], "toward": site["toward"]}
	out.merge(_dropoff(site, cfg))
	return out


## Where the group is set down for a site: on the site's own track, `cfg.dropoff.outside`
## metres outside the zone (straight-line from its middle), found walking down the track from
## the site. The ride is a fade, so nothing is gained by starting at the road; this far out
## the site, or the track up to it, is in view, and the zone (and any clock) starts a short
## walk on. A track that never gets that far (the site stands by a road) continues along the
## road it meets, the way leading off from the site; a site with no track gets the spot
## straight out from the side its track would leave by. {dropoff (x, z; the caller puts it
## on the ground), up (unit, on the ground plane: toward the site along the way), across
## (unit, square to it), car_off (metres from the way's middle to the car's, so it stands
## beside the way, not on it)}.
static func _dropoff(site: Dictionary, cfg: Dictionary) -> Dictionary:
	var drop: Dictionary = cfg.get("dropoff", {})
	var centre: Vector3 = site["centre"]
	var foot: Rect2 = site["footprint"]
	var reach := zone_radius(foot, cfg) + float(drop.get("outside", 25.0))
	var gap := float(drop.get("car_gap", 1.6))
	var middle := Vector2(centre.x, centre.z)
	var track: Dictionary = site.get("track", {})
	if track.is_empty():
		var toward: Vector3 = site["toward"]
		return _way(centre + toward * reach, -toward, gap)
	var points: PackedVector2Array = track["points"]
	var half := float(track["track_width"]) / 2.0
	for k in range(1, points.size()):
		var a := points[k - 1]
		var b := points[k]
		if b.distance_to(middle) < reach:
			continue
		var t := _crossing(a - middle, b - a, reach)
		var p := a.lerp(b, t)
		var up := Vector3(a.x - b.x, 0.0, a.y - b.y).normalized()
		return _way(Vector3(p.x, centre.y, p.y), up, half + gap)
	var end: Vector3 = track["end"]
	var along: Vector3 = track["along"]
	var from := Vector2(end.x, end.z)
	var dir := Vector2(along.x, along.z)
	if (from + dir).distance_to(middle) < (from - dir).distance_to(middle):
		dir = -dir
	var t := _crossing(from - middle, dir, reach)
	var at := from + dir * t
	var back := Vector3(middle.x - at.x, 0.0, middle.y - at.y).normalized()
	var out := _way(Vector3(at.x, centre.y, at.y), back, float(track["width"]) / 2.0 + gap)
	# Along the road, not across it toward the site.
	out["across"] = Vector3(dir.x, 0.0, dir.y).cross(Vector3.UP).normalized()
	return out


static func _way(at: Vector3, up: Vector3, car_off: float) -> Dictionary:
	return {"dropoff": at, "up": up, "across": up.cross(Vector3.UP).normalized(), "car_off": car_off}


## The share `t` of `step` from `from` (both relative to a circle's middle) where the point
## first reaches `radius` out; 1 when it never does, 0 when it is out already.
static func _crossing(from: Vector2, step: Vector2, radius: float) -> float:
	var a := step.dot(step)
	var b := 2.0 * from.dot(step)
	var c := from.dot(from) - radius * radius
	if c >= 0.0:
		return 0.0
	if a <= 0.0:
		return 1.0
	return (-b + sqrt(b * b - 4.0 * a * c)) / (2.0 * a)


## The place a mission at `site` (as `describe` gives it) happens: {centre, footprint,
## toward, dropoff, up, across, car_off, facing (the way the car's nose points: toward the
## site)}.
static func at_site(site: Dictionary, _cfg: Dictionary) -> Dictionary:
	return {"centre": site["centre"], "footprint": site["footprint"], "toward": site["toward"], "dropoff": site["dropoff"],
		"up": site["up"], "across": site["across"], "car_off": site["car_off"], "facing": site["up"]}


## The place a roadside mission happens, `metres` along the highway (`road_at` maps metres
## to a point on it): the zone's centre `ahead` metres further along and `off_road` metres
## to the right of the road, so the car stands clear of what is there; the drop-off
## `cfg.dropoff_side` metres right of the road's middle at `metres`, the car on it facing
## along the road. Its footprint is empty and its `toward` points back at the road.
static func roadside(road_at: Callable, metres: float, ahead: float, off_road: float, cfg: Dictionary) -> Dictionary:
	var on_road: Vector3 = road_at.call(metres)
	var dir := _direction(road_at, metres)
	var right := dir.cross(Vector3.UP).normalized()
	var there: Vector3 = road_at.call(metres + ahead)
	var there_right := _direction(road_at, metres + ahead).cross(Vector3.UP).normalized()
	var centre := there + there_right * off_road
	var drop := on_road + right * float(cfg.get("dropoff_side", 5.0))
	var up := Vector3(centre.x - drop.x, 0.0, centre.z - drop.z)
	up = up.normalized() if up.length() > 0.001 else right
	return {"centre": centre, "footprint": Rect2(Vector2(centre.x, centre.z), Vector2.ZERO), "toward": -there_right,
		"dropoff": drop, "up": up, "across": dir, "car_off": 0.0, "facing": dir}


static func _direction(road_at: Callable, metres: float) -> Vector3:
	var d: Vector3 = (road_at.call(metres + 1.0) as Vector3) - (road_at.call(metres) as Vector3)
	d.y = 0.0
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD


## How far from the middle of `foot` its edge lies the way `dir` (on the ground plane) points.
static func edge(foot: Rect2, dir: Vector3) -> float:
	var half := foot.size / 2.0
	var x := half.x / absf(dir.x) if absf(dir.x) > 0.0001 else INF
	var z := half.y / absf(dir.z) if absf(dir.z) > 0.0001 else INF
	return minf(x, z) if minf(x, z) < INF else 0.0

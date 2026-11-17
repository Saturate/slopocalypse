class_name SmokeVolume
extends RefCounted
## One plume as the server and every client see it: a sphere that grows from `r0` to `r1`
## over `grow` seconds, drifts with `wind` and rises at `rise`, and thins out over the last
## third of its `lifetime`. Everything here is a function of age, so clients advance a plume
## from its spawn event alone and land where the server's copy is.

## Share of the lifetime spent at full density before it starts thinning.
const FULL_SHARE := 2.0 / 3.0

var id := 0
var source := ""
var origin := Vector3.ZERO
var r0 := 1.0
var r1 := 1.0
var grow := 1.0
var lifetime := 1.0
var density := 1.0
var wind := Vector3.ZERO
var rise := 0.0
var seed := 0
var age := 0.0


static func from_payload(p: Dictionary) -> SmokeVolume:
	var v := SmokeVolume.new()
	v.id = int(p["id"])
	v.source = str(p["source"])
	v.origin = p["position"]
	v.r0 = float(p["r0"])
	v.r1 = float(p["r1"])
	v.grow = float(p["grow"])
	v.lifetime = float(p["lifetime"])
	v.density = float(p["density"])
	v.wind = p["wind"]
	v.rise = float(p["rise"])
	v.seed = int(p["seed"])
	return v


func to_payload() -> Dictionary:
	return {
		"id": id, "source": source, "position": origin, "r0": r0, "r1": r1, "grow": grow,
		"lifetime": lifetime, "density": density, "wind": wind, "rise": rise, "seed": seed,
	}


## Eases out: a plume puffs up fast and then spreads slowly.
func radius_at(t: float) -> float:
	var k := clampf(t / maxf(grow, 0.001), 0.0, 1.0)
	return lerpf(r0, r1, 1.0 - (1.0 - k) * (1.0 - k))


func centre_at(t: float) -> Vector3:
	return origin + (wind + Vector3.UP * rise) * maxf(t, 0.0)


func density_at(t: float) -> float:
	if t >= lifetime:
		return 0.0
	var thin_from := lifetime * FULL_SHARE
	if t <= thin_from:
		return density
	return density * (lifetime - t) / (lifetime - thin_from)


func ended() -> bool:
	return age >= lifetime


## How much smoke a line from `from` to `to` passes through now: density times the length
## of the line inside the sphere.
func along(from: Vector3, to: Vector3) -> float:
	var d := density_at(age)
	if d <= 0.0:
		return 0.0
	return d * inside_length(from, to, centre_at(age), radius_at(age))


static func inside_length(from: Vector3, to: Vector3, centre: Vector3, radius: float) -> float:
	var seg := to - from
	var length := seg.length()
	if length < 0.0001:
		return 0.0
	var dir := seg / length
	var rel := from - centre
	var b := rel.dot(dir)
	var c := rel.length_squared() - radius * radius
	var disc := b * b - c
	if disc <= 0.0:
		return 0.0
	var root := sqrt(disc)
	var enter := clampf(-b - root, 0.0, length)
	var leave := clampf(-b + root, 0.0, length)
	return leave - enter

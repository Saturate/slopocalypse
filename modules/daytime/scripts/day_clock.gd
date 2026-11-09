class_name DayClock
extends RefCounted
## The time of day as an hour in [0, 24), how fast it runs, and what the sky and light
## look like at any hour. Pure: no nodes, so the server and every client compute the same
## thing from the same hour.

const CONFIG := "res://modules/daytime/data/daytime.json"
const REQUIRED := {
	"start_hour": TYPE_FLOAT,
	"hour_seconds": TYPE_FLOAT,
	"night_speed": TYPE_FLOAT,
	"sync_seconds": TYPE_FLOAT,
	"sunrise": TYPE_FLOAT,
	"sunset": TYPE_FLOAT,
	"sun_max_elevation": TYPE_FLOAT,
	"moon_max_elevation": TYPE_FLOAT,
	"min_elevation": TYPE_FLOAT,
	"rise_azimuth": TYPE_FLOAT,
	"set_azimuth": TYPE_FLOAT,
	"update_seconds": TYPE_FLOAT,
	"keys": TYPE_ARRAY,
}
const COLOURS: Array[String] = ["light_color", "sky_top", "sky_horizon", "ground", "ambient_color", "fog_color"]
const NUMBERS: Array[String] = ["light_energy", "ambient", "sky_light", "fog_density", "exposure", "stars"]

var config: Dictionary
var hour: float


func _init(data: Dictionary) -> void:
	config = data
	hour = wrapf(float(data["start_hour"]), 0.0, 24.0)


func set_hour(to: float) -> void:
	hour = wrapf(to, 0.0, 24.0)


func is_night() -> bool:
	return hour < float(config["sunrise"]) or hour >= float(config["sunset"])


## 1 in full day, 0 at night, ramping over the hour around sunrise and sunset.
func daylight() -> float:
	var rise: float = config["sunrise"]
	var dusk: float = config["sunset"]
	var morning := clampf((hour - rise + 0.5), 0.0, 1.0)
	var evening := clampf((dusk + 0.5 - hour), 0.0, 1.0)
	return minf(morning, evening)


## Game hours per real second right now: the night runs `night_speed` times faster.
func rate() -> float:
	var per_hour := 1.0 / float(config["hour_seconds"])
	return per_hour * float(config["night_speed"]) if is_night() else per_hour


func advance(delta: float) -> void:
	set_hour(hour + rate() * delta)


## Direction the light shines (from the sun by day, from the moon by night) as a Basis
## whose -Z points along the light, like a DirectionalLight3D.
func light_basis() -> Basis:
	var rise: float = config["sunrise"]
	var dusk: float = config["sunset"]
	var t: float
	var top: float
	if is_night():
		var since := hour - dusk if hour >= dusk else hour + 24.0 - dusk
		t = since / (24.0 - dusk + rise)
		top = config["moon_max_elevation"]
	else:
		t = (hour - rise) / (dusk - rise)
		top = config["sun_max_elevation"]
	var elevation := maxf(top * sin(PI * t), float(config["min_elevation"]))
	var azimuth := lerpf(float(config["rise_azimuth"]), float(config["set_azimuth"]), t)
	return Basis.from_euler(Vector3(deg_to_rad(-elevation), deg_to_rad(azimuth), 0.0))


## How the world looks at this hour: colours and numbers blended between the two nearest
## keys, wrapping past midnight.
func look() -> Dictionary:
	var keys: Array = config["keys"]
	var after := 0
	while after < keys.size() and float((keys[after] as Dictionary)["hour"]) <= hour:
		after += 1
	var a: Dictionary = keys[(after - 1 + keys.size()) % keys.size()]
	var b: Dictionary = keys[after % keys.size()]
	var from := float(a["hour"])
	var to := float(b["hour"])
	var span := wrapf(to - from, 0.0, 24.0)
	var into := wrapf(hour - from, 0.0, 24.0)
	var w := into / span if span > 0.0 else 0.0
	var out := {}
	for field in COLOURS:
		out[field] = _colour(a[field]).lerp(_colour(b[field]), w)
	for field in NUMBERS:
		out[field] = lerpf(float(a[field]), float(b[field]), w)
	return out


static func _colour(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))


## The clock from data, or null (with the reason logged) when the file is wrong.
static func from_data() -> DayClock:
	var data: Variant = Data.load_json(CONFIG)
	if not data is Dictionary or not Data.require(CONFIG, data, REQUIRED):
		return null
	return DayClock.new(data)

extends GdUnitTestSuite
## Missions go to the map's sites: each offer takes a site of a kind its template names,
## within the template's distance of the camp, never one another offer has; the same seed
## gives the same picks; a template with no fitting site goes beside the highway only when it
## allows that (or the map has no sites at all). The group is set down on the site's own
## track a short walk outside the zone.

const MISSIONS := "res://modules/missions/missions_module.gd"
const CONFIG := "res://modules/missions/data/missions.json"
const HOME := Vector3(0.0, 0.0, 0.0)


func _config() -> Dictionary:
	return Data.load_json(CONFIG)


static func _roll(cfg: Dictionary, seed_value: int, sites: Array) -> Array:
	return (load(MISSIONS) as GDScript).call(&"roll_offers", cfg, seed_value, sites, HOME)


## A site of `kind` `metres` east of the camp, its track running `track` metres north from
## its pad to a road along x.
static func _site(kind: String, metres: float, track := 200.0) -> Dictionary:
	var centre := Vector3(metres, 0.0, 0.0)
	var points := PackedVector2Array()
	var z := -8.0
	while z > -8.0 - track:
		points.append(Vector2(metres, z))
		z -= 4.0
	points.append(Vector2(metres, -8.0 - track))
	return {"kind": kind, "centre": centre, "footprint": Rect2(metres - 10.0, -8.0, 20.0, 16.0), "toward": Vector3.FORWARD,
		"remoteness": 0.5, "track": {"points": points, "track_width": 3.5, "end": Vector3(metres, 0.0, -8.0 - track), "up": Vector3.BACK,
			"along": Vector3.RIGHT, "width": 7.0, "length": track}}


## Every kind the shipped templates use, at distances from close to the far side of a map.
static func _map() -> Array:
	var out := []
	for kind: String in ["farm", "cabin", "antenna", "lookout", "water_tower", "town_tower"]:
		for metres: float in [120.0, 400.0, 700.0, 1100.0, 1600.0, 2300.0]:
			out.append(_site(kind, metres + out.size()))
	return out


func test_offers_take_sites_of_their_kinds_within_their_distance() -> void:
	var cfg := _config()
	var sites := _map()
	var templates := {}
	for t: Dictionary in cfg["missions"]:
		templates[str(t["place"])] = t
	var at_sites := 0
	for seed_value in 40:
		for offer: Dictionary in _roll(cfg, seed_value, sites):
			var t: Dictionary = templates[str(offer["place"])]
			var kinds: Array = t.get("sites", ["roadside"])
			var site: Dictionary = offer["site"]
			if site.is_empty():
				assert_bool(kinds.has("roadside")).override_failure_message("%s went roadside" % offer["place"]).is_true()
				continue
			at_sites += 1
			assert_bool(kinds.has("any") or kinds.has(site["kind"])).override_failure_message("%s at a %s" % [offer["place"], site["kind"]]).is_true()
			var d := (site["centre"] as Vector3).distance_to(HOME)
			assert_float(d).is_between(float(t["distance"][0]), float(t["distance"][1]))
			assert_float(float(offer["distance"])).is_equal_approx(snappedf(d, 10.0), 0.01)
	assert_int(at_sites).is_greater(60)


func test_no_two_offers_share_a_site() -> void:
	var cfg := _config()
	var sites := _map()
	for seed_value in 40:
		var used := {}
		for offer: Dictionary in _roll(cfg, seed_value, sites):
			var site: Dictionary = offer["site"]
			if site.is_empty():
				continue
			assert_bool(used.has(site["index"])).is_false()
			used[site["index"]] = true


func test_when_sites_run_short_offers_still_never_share_one() -> void:
	var cfg := _config()
	var farm: Dictionary = (cfg["missions"] as Array).filter(func(t: Dictionary) -> bool: return t["place"] == "Farmstead")[0]
	cfg["missions"] = [farm, farm.duplicate(), farm.duplicate()]
	var offers := _roll(cfg, 3, [_site("farm", 400.0), _site("farm", 800.0), _site("cabin", 600.0)])
	# Two farms for three farm offers: the third has nowhere to go and is not offered.
	assert_int(offers.size()).is_equal(2)
	assert_int(int(offers[0]["site"]["index"])).is_not_equal(int(offers[1]["site"]["index"]))


func test_the_same_seed_picks_the_same_sites() -> void:
	var cfg := _config()
	var sites := _map()
	for seed_value in 10:
		assert_array(_roll(cfg, seed_value, sites)).is_equal(_roll(cfg, seed_value, sites))


func test_a_template_without_a_fitting_site_goes_roadside_only_if_it_may() -> void:
	var rng := RandomNumberGenerator.new()
	var far := [_site("cabin", 5000.0)]
	var cabin := {"sites": ["cabin"], "distance": [300.0, 900.0]}
	var depot := {"sites": ["any", "roadside"], "distance": [300.0, 900.0]}
	assert_int(MissionSites.pick(cabin, far, HOME, {}, rng)).is_equal(MissionSites.NOWHERE)
	assert_int(MissionSites.pick(depot, far, HOME, {}, rng)).is_equal(MissionSites.ROADSIDE_SPOT)
	# The flat test world has no sites at all: everything goes beside the road there.
	assert_int(MissionSites.pick(cabin, [], HOME, {}, rng)).is_equal(MissionSites.ROADSIDE_SPOT)


func test_the_drop_off_is_on_the_sites_own_track_a_walk_outside_the_zone() -> void:
	var cfg := _config()
	var site := MissionSites.describe(_site("farm", 400.0), 0, cfg)
	var place := MissionSites.at_site(site, cfg)
	var drop: Vector3 = place["dropoff"]
	var centre: Vector3 = site["centre"]
	var reach := MissionSites.zone_radius(site["footprint"], cfg) + float(cfg["dropoff"]["outside"])
	# On the track (x = 400 here), that far from the site's middle, facing up the track.
	assert_float(drop.x).is_equal_approx(400.0, 0.001)
	assert_float(Vector2(drop.x - centre.x, drop.z - centre.z).length()).is_equal_approx(reach, 0.01)
	assert_vector(place["up"] as Vector3).is_equal_approx(Vector3.BACK, Vector3.ONE * 0.001)
	# The car stands beside the track, not on it.
	assert_float(float(place["car_off"])).is_greater(3.5 / 2.0 + 1.0)


func test_a_short_track_carries_on_along_the_road_it_meets() -> void:
	var cfg := _config()
	var site := MissionSites.describe(_site("lookout", 400.0, 6.0), 0, cfg)
	var drop: Vector3 = MissionSites.at_site(site, cfg)["dropoff"]
	var centre: Vector3 = site["centre"]
	var reach := MissionSites.zone_radius(site["footprint"], cfg) + float(cfg["dropoff"]["outside"])
	# Along the road at the track's mouth (z = -14), out to the same walk from the zone.
	assert_float(drop.z).is_equal_approx(-14.0, 0.001)
	assert_float(Vector2(drop.x - centre.x, drop.z - centre.z).length()).is_equal_approx(reach, 0.01)

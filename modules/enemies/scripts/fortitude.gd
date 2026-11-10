class_name Fortitude
extends RefCounted
## How much fight a soldier has left, after Ryan McBeth's "How to simulate fear in video
## games". Each soldier rolls a fixed starting fortitude; the total moves with what is
## happening around it (allies in sight, pinned or in cover, wounded, out of ammo, a leader
## near or lost), and the total's band decides what it does: fight, hold (posture), flee
## or give up (submit). Pure rules over numbers from `enemies.json`.

const FIGHT := &"fight"
const POSTURE := &"posture"
const FLEE := &"flee"
const SUBMIT := &"submit"


## A starting fortitude in the config's `start` range.
static func roll(cfg: Dictionary, rng: RandomNumberGenerator) -> int:
	var r: Array = cfg.get("start", [0, 20])
	return rng.randi_range(int(r[0]), int(r[1]))


## The total for `start` given the situation: `{ally_in_sight, pinned, in_cover, wounded,
## out_of_ammo, leader_in_sight, leader_lost}` (missing keys count as false).
static func total(cfg: Dictionary, start: int, s: Dictionary) -> int:
	var step := int(cfg.get("step", 2))
	var steady := start >= int(cfg.get("steady_from", 18))
	var t := start
	t += step if s.get("ally_in_sight", false) else -step
	if s.get("pinned", false):
		t -= step
	elif s.get("in_cover", false):
		t += step
	if s.get("wounded", false) and not steady:
		t -= step
	if s.get("out_of_ammo", false) and not steady:
		t -= step
	if s.get("leader_in_sight", false):
		t += step
	if s.get("leader_lost", false):
		t -= step
	return t


## What a soldier with this total does.
static func band(cfg: Dictionary, value: int) -> StringName:
	var bands: Dictionary = cfg.get("bands", {})
	if value >= int(bands.get("fight", 17)):
		return FIGHT
	if value >= int(bands.get("posture", 11)):
		return POSTURE
	if value >= int(bands.get("flee", 5)):
		return FLEE
	return SUBMIT

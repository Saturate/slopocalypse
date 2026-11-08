class_name SoundBank
extends RefCounted
## Every sound in the game, synthesised once at runtime from noise and tones: no recorded
## audio, so nothing to license. Each is a short mono 16-bit AudioStreamWAV, cached by name.

const RATE := 44100

static var _cache: Dictionary[String, AudioStreamWAV] = {}


static func get_sound(sound: String) -> AudioStreamWAV:
	if _cache.has(sound):
		return _cache[sound]
	var samples := PackedFloat32Array()
	var looped := false
	match sound:
		"rifle": samples = _shot(0.42, 70.0, 1.0, 9000.0, 1)
		"pistol": samples = _shot(0.3, 110.0, 0.8, 7000.0, 2)
		"suppressed": samples = _shot(0.16, 140.0, 0.35, 1800.0, 3)
		"impact": samples = _thud(0.09, 900.0, 4)
		"hit": samples = _tick()
		"explosion": samples = _boom()
		"footstep": samples = _thud(0.07, 500.0, 5)
		"reload": samples = _clicks()
		"pickup": samples = _blip()
		"hurt": samples = _hurt()
		"dive": samples = _dive()
		"wind":
			samples = _wind()
			looped = true
		"rotor":
			samples = _rotor()
			looped = true
	if samples.is_empty():
		return null
	var stream := _to_wav(samples, looped)
	_cache[sound] = stream
	return stream


## A gunshot: a sharp noise crack that dies fast, a low thump under it, and a tail.
## `body_hz` is the thump's pitch, `bright_hz` how much of the crack gets through.
static func _shot(seconds: float, body_hz: float, crack: float, bright_hz: float, seed: int) -> PackedFloat32Array:
	var rng := _rng(seed)
	var out := PackedFloat32Array()
	var lp := 0.0
	var a := _one_pole(bright_hz)
	for i in int(seconds * RATE):
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * a
		var crack_env := exp(-t * 55.0) * crack
		var tail_env := exp(-t * 9.0) * 0.35
		var thump := sin(TAU * body_hz * t * (1.0 - t)) * exp(-t * 24.0) * 0.9
		out.append(clampf(lp * (crack_env + tail_env) * 1.6 + thump, -1.0, 1.0))
	return out


## A short muffled knock: impacts, footsteps.
static func _thud(seconds: float, bright_hz: float, seed: int) -> PackedFloat32Array:
	var rng := _rng(seed)
	var out := PackedFloat32Array()
	var lp := 0.0
	var a := _one_pole(bright_hz)
	for i in int(seconds * RATE):
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * a
		out.append(lp * exp(-t * 45.0) * 1.8 + sin(TAU * 90.0 * t) * exp(-t * 60.0) * 0.4)
	return out


## The hit marker: a bright, dry tick.
static func _tick() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in int(0.05 * RATE):
		var t := float(i) / RATE
		out.append(sin(TAU * 2600.0 * t) * exp(-t * 90.0) * 0.6 + sin(TAU * 1300.0 * t) * exp(-t * 70.0) * 0.3)
	return out


## A long low rumble with a hard start.
static func _boom() -> PackedFloat32Array:
	var rng := _rng(6)
	var out := PackedFloat32Array()
	var lp := 0.0
	var lp2 := 0.0
	var a := _one_pole(380.0)
	for i in int(1.8 * RATE):
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * a
		lp2 += (lp - lp2) * a
		var env := exp(-t * 2.6) + exp(-t * 30.0) * 1.5
		var thump := sin(TAU * 45.0 * t) * exp(-t * 6.0)
		out.append(clampf(lp2 * env * 4.0 + thump * 0.8, -1.0, 1.0))
	return out


## Magazine out, magazine in: two clicks a beat apart.
static func _clicks() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var rng := _rng(7)
	for i in int(0.45 * RATE):
		var t := float(i) / RATE
		var v := 0.0
		for at: float in [0.0, 0.32]:
			if t >= at:
				var u := t - at
				v += rng.randf_range(-1.0, 1.0) * exp(-u * 160.0) * 0.8 + sin(TAU * 1800.0 * u) * exp(-u * 120.0) * 0.4
		out.append(clampf(v, -1.0, 1.0))
	return out


## Two rising notes for picking something up.
static func _blip() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in int(0.16 * RATE):
		var t := float(i) / RATE
		var hz := 880.0 if t < 0.07 else 1320.0
		out.append(sin(TAU * hz * t) * 0.35 * minf(1.0, (0.16 - t) * 30.0))
	return out


## A drone diving: a buzzing whine rising in pitch, as a warning.
static func _dive() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var phase := 0.0
	for i in int(1.4 * RATE):
		var t := float(i) / RATE
		var hz := lerpf(380.0, 1400.0, pow(t / 1.4, 1.5))
		phase += TAU * hz / RATE
		var buzz := sin(phase) + 0.4 * sin(phase * 2.0) + 0.25 * signf(sin(phase * 0.5))
		out.append(buzz * 0.35 * minf(1.0, t * 6.0))
	return out


## A drone's rotors: a buzzing tone with its harmonics, chopped by the blades, over a hiss.
## Every frequency is a whole number of cycles in the one-second loop, so it never clicks.
static func _rotor() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var rng := _rng(10)
	var lp := 0.0
	var a := _one_pole(2400.0)
	for i in RATE:
		var t := float(i) / RATE
		var tone := sin(TAU * 170.0 * t) + 0.5 * sin(TAU * 340.0 * t) + 0.25 * sin(TAU * 510.0 * t)
		var chop := 0.7 + 0.3 * sin(TAU * 34.0 * t)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * a
		out.append((tone * 0.28 * chop + lp * 0.35) * 0.8)
	return out


## Getting hit: a dull low blow.
static func _hurt() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var rng := _rng(8)
	for i in int(0.25 * RATE):
		var t := float(i) / RATE
		out.append(sin(TAU * 70.0 * t) * exp(-t * 14.0) * 0.8 + rng.randf_range(-1.0, 1.0) * exp(-t * 40.0) * 0.2)
	return out


## Soft wind that loops without a seam: filtered noise faded in at the start and out at
## the end over the same samples.
static func _wind() -> PackedFloat32Array:
	var rng := _rng(9)
	var n := int(6.0 * RATE)
	var raw := PackedFloat32Array()
	var lp := 0.0
	var a := _one_pole(260.0)
	for i in n:
		lp += (rng.randf_range(-1.0, 1.0) - lp) * a
		var gust := 0.6 + 0.4 * sin(TAU * float(i) / n * 2.0)
		raw.append(lp * 3.0 * gust)
	var fade := int(0.5 * RATE)
	var out := PackedFloat32Array()
	for i in n - fade:
		var v := raw[i]
		if i < fade:
			var w := float(i) / fade
			v = raw[i] * w + raw[n - fade + i] * (1.0 - w)
		out.append(clampf(v, -1.0, 1.0))
	return out


static func _to_wav(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples.size()
	return wav


## Coefficient for a one-pole low-pass at `hz`.
static func _one_pole(hz: float) -> float:
	return 1.0 - exp(-TAU * hz / RATE)


## Sounds are the same every run: seeded noise.
static func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

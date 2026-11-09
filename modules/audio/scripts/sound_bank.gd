class_name SoundBank
extends RefCounted
## Every sound in the game, synthesised once at runtime from noise and tones: no recorded
## audio, so nothing to license. Each is a short mono 16-bit AudioStreamWAV, cached by name.

const RATE := 44100
## The wind loop is long so nobody hears it repeat.
const WIND_SECONDS := 24.0
## Different bird songs, asked for as "bird0", "bird1", ...
const BIRD_VARIANTS := 4

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
		"crickets":
			samples = _crickets()
			looped = true
		_:
			if sound.begins_with("bird"):
				samples = _bird(int(sound.trim_prefix("bird")))
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


## A mild breeze that loops without a seam: soft mid-band noise for the air, a faint brighter
## rustle for leaves, both swelling on slow gusts that never repeat on a beat (several slow
## waves at unrelated rates). Long, so the loop isn't heard; no low rumble, which reads as surf.
static func _wind() -> PackedFloat32Array:
	var rng := _rng(9)
	var n := int(WIND_SECONDS * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n)
	var low := 0.0
	var high := 0.0
	var rustle_low := 0.0
	var rustle_high := 0.0
	var air_hp := _one_pole(180.0)
	var air_lp := _one_pole(900.0)
	var leaf_hp := _one_pole(1800.0)
	var leaf_lp := _one_pole(5200.0)
	for i in n:
		var t := float(i) / RATE
		var white := rng.randf_range(-1.0, 1.0)
		# Band-pass as the difference of two low-passes.
		low += (white - low) * air_hp
		high += (white - high) * air_lp
		var air := high - low
		rustle_low += (white - rustle_low) * leaf_hp
		rustle_high += (white - rustle_high) * leaf_lp
		var leaves := rustle_high - rustle_low
		var gust := 0.55 + 0.2 * sin(TAU * t / 7.3) + 0.15 * sin(TAU * t / 3.1 + 1.7) + 0.1 * sin(TAU * t / 11.9 + 0.4)
		var flutter := maxf(0.0, sin(TAU * t / 2.3 + 0.9) * sin(TAU * t / 5.7))
		raw[i] = air * 2.2 * gust + leaves * 1.6 * (0.3 + flutter) * gust
	return _seamless(raw, int(0.8 * RATE))


## Crossfades the end of a sound into its start, so it loops without a click.
static func _seamless(raw: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	var n := raw.size()
	var out := PackedFloat32Array()
	out.resize(n - fade)
	for i in n - fade:
		var v := raw[i]
		if i < fade:
			var w := float(i) / fade
			v = raw[i] * w + raw[n - fade + i] * (1.0 - w)
		out[i] = clampf(v, -1.0, 1.0)
	return out


## One songbird phrase. Each variant is its own little song: quick rising chirps, a trill,
## a falling whistle, or a two-note call. A sine whose pitch is swept and wobbled, shaped
## with short fades so nothing clicks.
static func _bird(variant: int) -> PackedFloat32Array:
	var rng := _rng(40 + variant)
	var out := PackedFloat32Array()
	match variant % BIRD_VARIANTS:
		0:
			# Rising chirps, three to five of them.
			for c in rng.randi_range(3, 5):
				_note(out, 0.07, 2600.0, 4400.0, 0.0, 0.0)
				_rest(out, rng.randf_range(0.05, 0.09))
		1:
			# A fast trill that slows and drops at the end.
			for c in 9:
				var top := 3800.0 - c * 90.0
				_note(out, 0.035 + c * 0.004, top, top - 600.0, 0.0, 0.0)
				_rest(out, 0.018 + c * 0.004)
		2:
			# A long falling whistle with a little vibrato.
			_note(out, 0.55, 3400.0, 2100.0, 18.0, 70.0)
		_:
			# Two clear notes, high then lower, sometimes repeated.
			for r in rng.randi_range(1, 2):
				_note(out, 0.18, 2900.0, 3000.0, 0.0, 0.0)
				_rest(out, 0.07)
				_note(out, 0.24, 2300.0, 2200.0, 6.0, 30.0)
				_rest(out, 0.25)
	return out


## Appends a swept sine note: from `from_hz` to `to_hz` over `seconds`, with vibrato.
static func _note(out: PackedFloat32Array, seconds: float, from_hz: float, to_hz: float, vibrato_hz: float, vibrato_depth: float) -> void:
	var n := int(seconds * RATE)
	var phase := 0.0
	var edge := mini(int(0.008 * RATE), n / 2)
	for i in n:
		var t := float(i) / n
		var hz := lerpf(from_hz, to_hz, t) + sin(TAU * vibrato_hz * float(i) / RATE) * vibrato_depth
		phase += TAU * hz / RATE
		var env := minf(1.0, minf(float(i) / maxf(edge, 1), float(n - i) / maxf(edge, 1)))
		# A touch of the octave makes it sound like a throat rather than a test tone.
		out.append((sin(phase) + 0.18 * sin(phase * 2.0)) * 0.5 * env)


static func _rest(out: PackedFloat32Array, seconds: float) -> void:
	for i in int(seconds * RATE):
		out.append(0.0)


## Night crickets that loop: a high tone pulsed in quick bursts, two insects slightly out of
## step, under a breath of noise.
static func _crickets() -> PackedFloat32Array:
	var rng := _rng(77)
	var n := int(4.0 * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var t := float(i) / RATE
		var a := _cricket(t, 4700.0, 0.0, 0.53)
		var b := _cricket(t, 4300.0, 0.21, 0.71)
		raw[i] = (a + b * 0.7) * 0.35 + rng.randf_range(-1.0, 1.0) * 0.01
	return _seamless(raw, int(0.3 * RATE))


## One cricket: chirps of 3 pulses, one every `period` seconds.
static func _cricket(t: float, hz: float, offset: float, period: float) -> float:
	var into := fposmod(t + offset, period)
	var pulse := into / 0.016
	if pulse >= 6.0 or int(pulse) % 2 == 1:
		return 0.0
	return sin(TAU * hz * t) * sin(PI * fposmod(pulse, 1.0))


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

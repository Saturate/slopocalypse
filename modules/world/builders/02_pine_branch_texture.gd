extends SceneTree
## Paints modules/world/textures/generated/pine_branch.png: one conifer branch (stem, side
## twigs, needles) on transparency, for tree branch cards. Procedural because no CC0 conifer
## branch atlas exists; seeded so the output is identical every run.
## The branch runs left (trunk end) to right (tip) across the image.

const OUT := "res://modules/world/textures/generated/pine_branch.png"
const W := 512
const H := 256

var _img: Image
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = 20261106
	_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 0))
	var stem_color := Color(0.28, 0.2, 0.14)
	# Main stem with a slight droop toward the tip.
	var points: Array[Vector2] = []
	for i in 41:
		var t := float(i) / 40.0
		points.append(Vector2(4.0 + t * (W - 24.0), H * 0.5 + t * t * 26.0))
	for i in points.size() - 1:
		_line(points[i], points[i + 1], stem_color, lerpf(4.0, 1.5, float(i) / points.size()))
	# Side twigs branch off forward at alternating sides.
	for i in range(4, points.size() - 4, 3):
		var base := points[i]
		var side := 1.0 if (i / 3) % 2 == 0 else -1.0
		var length := lerpf(110.0, 40.0, float(i) / points.size())
		var tip := base + Vector2(length * 0.75, side * length * 0.55 + 10.0)
		_line(base, tip, stem_color, 1.6)
		_needles(base, tip, length * 0.28)
	_needles(points[0], points[points.size() - 1], 34.0)
	_img.save_png(OUT)
	quit(0)


## Needles along a twig: short dark-green strokes angled forward on both sides, shorter
## toward the tip, with per-needle colour variation.
func _needles(from: Vector2, to: Vector2, length: float) -> void:
	var dir := (to - from).normalized()
	var normal := Vector2(-dir.y, dir.x)
	var span := from.distance_to(to)
	var steps := int(span / 2.5)
	for s in steps:
		var t := float(s) / maxf(steps, 1)
		var at := from.lerp(to, t)
		var l := length * lerpf(1.0, 0.55, t) * _rng.randf_range(0.8, 1.15)
		for side: float in [-1.0, 1.0]:
			var angle := deg_to_rad(_rng.randf_range(40.0, 65.0))
			var needle_dir := (dir * cos(angle) + normal * side * sin(angle)).normalized()
			var c := Color(0.12, 0.2, 0.09).lerp(Color(0.22, 0.32, 0.14), _rng.randf())
			_line(at, at + needle_dir * l, c, 1.3)


## Anti-aliased-ish thick line: stamps soft dots along the segment, blending over what is there.
func _line(a: Vector2, b: Vector2, c: Color, thickness: float) -> void:
	var steps := int(a.distance_to(b)) + 1
	var r := thickness * 0.5
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		for y in range(int(p.y - r - 1), int(p.y + r + 2)):
			for x in range(int(p.x - r - 1), int(p.x + r + 2)):
				if x < 0 or y < 0 or x >= W or y >= H:
					continue
				var d := Vector2(x + 0.5, y + 0.5).distance_to(p)
				var alpha := clampf(r + 0.5 - d, 0.0, 1.0)
				if alpha <= 0.0:
					continue
				var under := _img.get_pixel(x, y)
				var out := under.lerp(Color(c.r, c.g, c.b, 1.0), alpha)
				out.a = maxf(under.a, alpha)
				_img.set_pixel(x, y, out)

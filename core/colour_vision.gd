class_name ColourVision
extends RefCounted
## How a colour looks to someone with one of the three common kinds of colour blindness, and
## how far apart two colours look, so colour choices (armbands, markers) can be checked by
## numbers and captures can be shown as a colour-blind player sees them.
##
## Simulation: Machado, Oliveira and Fernandes (2009), full-severity matrices, applied in
## linear RGB. Distance: Euclidean in OKLab, where about 0.02 is the smallest difference
## people notice side by side and 0.1 is plainly different.

const NORMAL := &"normal"
## Red (long-wavelength) cones missing, about 1 % of men: reds darken and fall towards olive.
const PROTAN := &"protan"
## Green cones missing (the most common, about 1 % of men, 5 % weak): red, orange, yellow
## and green become one yellow-olive axis told apart only by lightness.
const DEUTAN := &"deutan"
## Blue cones missing (rare): blue turns teal, yellow turns pink-white.
const TRITAN := &"tritan"
const KINDS: Array[StringName] = [NORMAL, PROTAN, DEUTAN, TRITAN]

const _MATRICES := {
	PROTAN: [Vector3(0.152286, 1.052583, -0.204868), Vector3(0.114503, 0.786281, 0.099216), Vector3(-0.003882, -0.048116, 1.051998)],
	DEUTAN: [Vector3(0.367322, 0.860646, -0.227968), Vector3(0.280085, 0.672501, 0.047413), Vector3(-0.011820, 0.042940, 0.968881)],
	TRITAN: [Vector3(1.255528, -0.076749, -0.178779), Vector3(-0.078411, 0.930809, 0.147602), Vector3(0.004733, 0.691367, 0.303900)],
}


## `colour` (sRGB) as someone with `kind` sees it.
static func simulate(colour: Color, kind: StringName) -> Color:
	if not _MATRICES.has(kind):
		return colour
	var rows: Array = _MATRICES[kind]
	var lin := colour.srgb_to_linear()
	var l := Vector3(lin.r, lin.g, lin.b)
	var out := Color((rows[0] as Vector3).dot(l), (rows[1] as Vector3).dot(l), (rows[2] as Vector3).dot(l), colour.a)
	return Color(clampf(out.r, 0.0, 1.0), clampf(out.g, 0.0, 1.0), clampf(out.b, 0.0, 1.0), colour.a).linear_to_srgb()


## OKLab of an sRGB colour: x lightness (0 black, 1 white), y green-red, z blue-yellow.
static func oklab(colour: Color) -> Vector3:
	var c := colour.srgb_to_linear()
	var l := pow(0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b, 1.0 / 3.0)
	var m := pow(0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b, 1.0 / 3.0)
	var s := pow(0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b, 1.0 / 3.0)
	return Vector3(
		0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


## How far apart `a` and `b` look to someone with `kind`.
static func difference(a: Color, b: Color, kind: StringName = NORMAL) -> float:
	return oklab(simulate(a, kind)).distance_to(oklab(simulate(b, kind)))


## `image` as someone with `kind` sees it (a new image; the original is left alone).
static func simulate_image(image: Image, kind: StringName) -> Image:
	var out := image.duplicate() as Image
	if out.is_compressed():
		out.decompress()
	out.convert(Image.FORMAT_RGBA8)
	if not _MATRICES.has(kind):
		return out
	for y in out.get_height():
		for x in out.get_width():
			out.set_pixel(x, y, simulate(out.get_pixel(x, y), kind))
	return out

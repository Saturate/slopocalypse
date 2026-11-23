// Reads the PNGs Godot saves (8-bit RGB or RGBA, not interlaced) into RGBA pixels, and the
// cheap checks a playtest makes on a screenshot. Hand-written on node:zlib so the tools keep
// no image dependency; anything Godot does not write is refused rather than guessed at.
import { deflateSync, inflateSync } from "node:zlib";

export interface Image {
	width: number;
	height: number;
	// RGBA, 4 bytes a pixel, rows top to bottom.
	data: Uint8Array;
}

const SIGNATURE = Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10]);

export function decodePng(file: Uint8Array): Image {
	for (let i = 0; i < SIGNATURE.length; i++) if (file[i] !== SIGNATURE[i]) throw new Error("not a PNG");
	const view = new DataView(file.buffer, file.byteOffset, file.byteLength);
	let at = 8;
	let width = 0;
	let height = 0;
	let channels = 0;
	const idat: Uint8Array[] = [];
	while (at + 8 <= file.length) {
		const length = view.getUint32(at);
		const type = String.fromCharCode(...file.subarray(at + 4, at + 8));
		const body = file.subarray(at + 8, at + 8 + length);
		if (type === "IHDR") {
			width = view.getUint32(at + 8);
			height = view.getUint32(at + 12);
			const depth = body[8];
			const colour = body[9];
			const interlace = body[12];
			if (depth !== 8 || (colour !== 2 && colour !== 6) || interlace !== 0) throw new Error(`unsupported PNG: depth ${depth}, colour type ${colour}, interlace ${interlace}`);
			channels = colour === 6 ? 4 : 3;
		} else if (type === "IDAT") {
			idat.push(body);
		} else if (type === "IEND") {
			break;
		}
		at += 12 + length;
	}
	if (channels === 0) throw new Error("PNG has no header");
	const raw = inflateSync(Buffer.concat(idat));
	const stride = width * channels;
	if (raw.length < height * (stride + 1)) throw new Error("PNG data is short");
	const out = new Uint8Array(width * height * 4);
	let prev = new Uint8Array(stride);
	for (let y = 0; y < height; y++) {
		const filter = raw[y * (stride + 1)];
		const line = Uint8Array.from(raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
		unfilter(filter ?? 0, line, prev, channels);
		for (let x = 0; x < width; x++) {
			const o = (y * width + x) * 4;
			out[o] = line[x * channels] ?? 0;
			out[o + 1] = line[x * channels + 1] ?? 0;
			out[o + 2] = line[x * channels + 2] ?? 0;
			out[o + 3] = channels === 4 ? (line[x * channels + 3] ?? 255) : 255;
		}
		prev = line;
	}
	return { width, height, data: out };
}

function paeth(a: number, b: number, c: number): number {
	const p = a + b - c;
	const pa = Math.abs(p - a);
	const pb = Math.abs(p - b);
	const pc = Math.abs(p - c);
	if (pa <= pb && pa <= pc) return a;
	return pb <= pc ? b : c;
}

function unfilter(filter: number, line: Uint8Array, prev: Uint8Array, bpp: number): void {
	for (let i = 0; i < line.length; i++) {
		const left = i >= bpp ? (line[i - bpp] ?? 0) : 0;
		const up = prev[i] ?? 0;
		const corner = i >= bpp ? (prev[i - bpp] ?? 0) : 0;
		const x = line[i] ?? 0;
		if (filter === 1) line[i] = (x + left) & 255;
		else if (filter === 2) line[i] = (x + up) & 255;
		else if (filter === 3) line[i] = (x + ((left + up) >> 1)) & 255;
		else if (filter === 4) line[i] = (x + paeth(left, up, corner)) & 255;
		else if (filter !== 0) throw new Error(`bad PNG filter ${filter}`);
	}
}

// An RGBA PNG without filtering, for tests and for writing crops.
export function encodePng(image: Image): Buffer {
	const rows = Buffer.alloc(image.height * (image.width * 4 + 1));
	for (let y = 0; y < image.height; y++) {
		rows[y * (image.width * 4 + 1)] = 0;
		rows.set(image.data.subarray(y * image.width * 4, (y + 1) * image.width * 4), y * (image.width * 4 + 1) + 1);
	}
	const header = Buffer.alloc(13);
	header.writeUInt32BE(image.width, 0);
	header.writeUInt32BE(image.height, 4);
	header.set([8, 6, 0, 0, 0], 8);
	return Buffer.concat([Buffer.from(SIGNATURE), chunk("IHDR", header), chunk("IDAT", deflateSync(rows)), chunk("IEND", Buffer.alloc(0))]);
}

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
	let c = n;
	for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
	return c >>> 0;
});

function crc32(bytes: Uint8Array): number {
	let c = 0xffffffff;
	for (const b of bytes) c = (CRC_TABLE[(c ^ b) & 255] ?? 0) ^ (c >>> 8);
	return (c ^ 0xffffffff) >>> 0;
}

function chunk(type: string, body: Buffer): Buffer {
	const head = Buffer.alloc(8);
	head.writeUInt32BE(body.length, 0);
	head.write(type, 4, "ascii");
	const crc = Buffer.alloc(4);
	crc.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), body])), 0);
	return Buffer.concat([head, body, crc]);
}

// A part of the image in fractions of its size (0..1), so a check holds at any resolution.
export interface Region {
	x: number;
	y: number;
	w: number;
	h: number;
}

export const WHOLE: Region = { x: 0, y: 0, w: 1, h: 1 };

export type Rgb = readonly [number, number, number];

export function parseColour(hex: string): Rgb {
	const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex);
	if (m === null) throw new Error(`not a colour: ${hex} (want #rrggbb)`);
	return [parseInt(m[1] ?? "0", 16), parseInt(m[2] ?? "0", 16), parseInt(m[3] ?? "0", 16)];
}

function pixelBox(image: Image, region: Region): { x0: number; y0: number; x1: number; y1: number } {
	const clamp = (v: number, max: number): number => Math.min(Math.max(Math.round(v), 0), max);
	const x0 = clamp(region.x * image.width, image.width);
	const y0 = clamp(region.y * image.height, image.height);
	return { x0, y0, x1: Math.max(clamp((region.x + region.w) * image.width, image.width), x0), y1: Math.max(clamp((region.y + region.h) * image.height, image.height), y0) };
}

export interface ColourMatch {
	// Pixels within `tolerance` of the colour.
	count: number;
	// Of all pixels in the region.
	share: number;
	// The nearest pixel found and its distance, so a miss says how close it came.
	nearest: Rgb;
	distance: number;
	// Where the matches are, as a fraction of the image (the centre of their bounding box).
	centre: [number, number] | undefined;
}

// Pixels in `region` whose RGB lies within `tolerance` (Euclidean, 0..441) of `colour`.
export function findColour(image: Image, colour: Rgb, tolerance: number, region: Region = WHOLE): ColourMatch {
	const { x0, y0, x1, y1 } = pixelBox(image, region);
	let count = 0;
	let best = Infinity;
	let nearest: Rgb = [0, 0, 0];
	let minX = Infinity;
	let minY = Infinity;
	let maxX = -Infinity;
	let maxY = -Infinity;
	for (let y = y0; y < y1; y++) {
		for (let x = x0; x < x1; x++) {
			const o = (y * image.width + x) * 4;
			const r = image.data[o] ?? 0;
			const g = image.data[o + 1] ?? 0;
			const b = image.data[o + 2] ?? 0;
			const d = Math.hypot(r - colour[0], g - colour[1], b - colour[2]);
			if (d < best) {
				best = d;
				nearest = [r, g, b];
			}
			if (d <= tolerance) {
				count++;
				minX = Math.min(minX, x);
				minY = Math.min(minY, y);
				maxX = Math.max(maxX, x);
				maxY = Math.max(maxY, y);
			}
		}
	}
	const total = (x1 - x0) * (y1 - y0);
	return {
		count,
		share: total > 0 ? count / total : 0,
		nearest,
		distance: Number.isFinite(best) ? Math.round(best) : Infinity,
		centre: count > 0 ? [(minX + maxX) / 2 / image.width, (minY + maxY) / 2 / image.height] : undefined,
	};
}

// Mean brightness of `region`, 0..255 (Rec. 709 luma of the stored sRGB values).
export function meanLuma(image: Image, region: Region = WHOLE): number {
	const { x0, y0, x1, y1 } = pixelBox(image, region);
	let sum = 0;
	for (let y = y0; y < y1; y++) {
		for (let x = x0; x < x1; x++) {
			const o = (y * image.width + x) * 4;
			sum += 0.2126 * (image.data[o] ?? 0) + 0.7152 * (image.data[o + 1] ?? 0) + 0.0722 * (image.data[o + 2] ?? 0);
		}
	}
	const total = (x1 - x0) * (y1 - y0);
	return total > 0 ? sum / total : 0;
}

// Pixels in `region` at least `by` brighter (luma) in `after` than in `before`: what a light
// switching on changed, with everything drawn in both (HUD, markers) cancelling out.
export function brighterPixels(before: Image, after: Image, by: number, region: Region = WHOLE): number {
	if (before.width !== after.width || before.height !== after.height) throw new Error(`images differ in size: ${before.width}x${before.height} and ${after.width}x${after.height}`);
	const { x0, y0, x1, y1 } = pixelBox(after, region);
	const luma = (d: Uint8Array, o: number): number => 0.2126 * (d[o] ?? 0) + 0.7152 * (d[o + 1] ?? 0) + 0.0722 * (d[o + 2] ?? 0);
	let count = 0;
	for (let y = y0; y < y1; y++) {
		for (let x = x0; x < x1; x++) {
			const o = (y * after.width + x) * 4;
			if (luma(after.data, o) - luma(before.data, o) >= by) count++;
		}
	}
	return count;
}

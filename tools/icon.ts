// The game logo, drawn in code: an S out of amber voxel tiles on a dark steel plate.
// The design is a letter of 5x7 tiles (S_ROWS) laid out fresh at every pixel size
// (layout), so a 16 px icon gets whole pixels for every tile rather than a shrunk copy
// of the big one; everything this tool writes is a rendering of that one layout, so the
// art is edited in one place:
//
//   node tools/icon.ts
//
//   icon.svg                  the project icon (config/icon in project.godot)
//   assets/logo/icon-<n>.png  the mark at a run of pixel sizes (the macOS app icon is 1024)
//   assets/logo/icon.ico      the Windows exe and window icon, and the server web page's favicon
//
// No dependencies: the PNG is encoded here (zlib and a CRC table), the .ico around it.

import { mkdirSync, writeFileSync } from "node:fs";
import { deflateSync } from "node:zlib";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");

// Colour indices into PALETTE.
export const CLEAR = 0;
export const PLATE = 1;
export const RIM = 2;
export const TILE = 3;
export const TILE_LIT = 4;
export const TILE_SHADE = 5;

// [hex, r, g, b]. The plate, rim and tile are the UI's own colours (core/ui/ui_palette.gd:
// BACKGROUND, STEEL, ACCENT; a tool test keeps them in step); lit and shaded are the
// accent a step up and down.
export const PALETTE: Array<[string, number, number, number]> = [
	["#000000", 0, 0, 0],
	["#16180f", 0x16, 0x18, 0x0f],
	["#3b4034", 0x3b, 0x40, 0x34],
	["#f2a516", 0xf2, 0xa5, 0x16],
	["#fbc65a", 0xfb, 0xc6, 0x5a],
	["#b3770c", 0xb3, 0x77, 0x0c],
];

// The S as a 5x7 block letter, with both of its ends (the top-right and bottom-left
// cells): without them it reads as a 5 or a 3 at a glance.
export const S_ROWS: readonly string[] = [
	".XXX.",
	"X...X",
	"X....",
	".XXX.",
	"....X",
	"X...X",
	".XXX.",
];
const COLS = 5;
const ROWS = 7;
// 128 px and up: a tile is 16 px, and a 2 px groove still leaves it solid.
const GROOVE_MIN_PITCH = 16;

export interface Rect {
	x: number;
	y: number;
	w: number;
	h: number;
	c: number;
}

export interface Layout {
	size: number;
	// Corner radius of the plate, in pixels.
	radius: number;
	// Steel rim inside the plate's edge, so the dark plate still has an outline on a
	// dark taskbar or tab bar.
	rim: number;
	// One tile step (the letter is 5 by 7 of them); 1/8 of the size, so the letter fills
	// 7/8 of the height, just inside the rim at 16 px.
	pitch: number;
	// Lit and shaded edge of each tile; 0 at the smallest sizes, where an edge pixel is
	// half the tile and turns the letter into stripes.
	bevel: number;
	// Whether neighbouring tiles in a stroke show the edge between them as a groove. Below
	// this the grooves chop the strokes into dots, so the letter is drawn as solid bars.
	grooved: boolean;
	// Every tile as filled rects, in paint order.
	rects: Rect[];
}

// Which sides of a tile get an edge: all four when the tiles are grooved, otherwise
// only the sides that face plate, so a stroke reads as one solid bar.
interface Sides {
	top: boolean;
	left: boolean;
	bottom: boolean;
	right: boolean;
}

function tileRects(x: number, y: number, t: number, b: number, sides: Sides): Rect[] {
	const out: Rect[] = [{ x, y, w: t, h: t, c: TILE }];
	if (b === 0) return out;
	// Order matters where edges cross: the top-right corner is lit, the bottom-left shaded.
	if (sides.right) out.push({ x: x + t - b, y, w: b, h: t, c: TILE_SHADE });
	if (sides.left) out.push({ x, y, w: b, h: t, c: TILE_LIT });
	if (sides.top) out.push({ x, y, w: t, h: b, c: TILE_LIT });
	if (sides.bottom) out.push({ x, y: y + t - b, w: t, h: b, c: TILE_SHADE });
	return out;
}

function filled(row: number, col: number): boolean {
	return S_ROWS[row]?.[col] === "X";
}

export function layout(size: number): Layout {
	if (!Number.isInteger(size) || size < 16) throw new Error(`icon: size ${size} (16 or more, whole pixels)`);
	const pitch = Math.floor(size / 8);
	const bevel = pitch >= 4 ? Math.round(pitch / 8) : 0;
	const grooved = pitch >= GROOVE_MIN_PITCH;
	const ox = Math.floor((size - COLS * pitch) / 2);
	const oy = Math.floor((size - ROWS * pitch) / 2);
	const rects: Rect[] = [];
	for (let row = 0; row < ROWS; row++)
		for (let col = 0; col < COLS; col++) {
			if (!filled(row, col)) continue;
			const sides: Sides = {
				top: grooved || !filled(row - 1, col),
				left: grooved || !filled(row, col - 1),
				bottom: grooved || !filled(row + 1, col),
				right: grooved || !filled(row, col + 1),
			};
			rects.push(...tileRects(ox + col * pitch, oy + row * pitch, pitch, bevel, sides));
		}
	return { size, radius: (size * 5) / 32, rim: Math.max(1, Math.round(size / 32)), pitch, bevel, grooved, rects };
}

// Pixel centres within `inset` of a rounded square of the given radius.
function inRounded(size: number, radius: number, inset: number, x: number, y: number): boolean {
	const r = Math.max(0, radius - inset);
	const px = x + 0.5;
	const py = y + 0.5;
	const lo = inset + r;
	const hi = size - inset - r;
	if (px < inset || py < inset || px > size - inset || py > size - inset) return false;
	const cx = px < lo ? lo : px > hi ? hi : px;
	const cy = py < lo ? lo : py > hi ? hi : py;
	return (px - cx) * (px - cx) + (py - cy) * (py - cy) <= r * r;
}

// The layout as palette indices, one per pixel.
export function rasterize(l: Layout): Uint8Array {
	const { size } = l;
	const g = new Uint8Array(size * size);
	for (let y = 0; y < size; y++)
		for (let x = 0; x < size; x++)
			if (inRounded(size, l.radius, 0, x, y)) g[y * size + x] = l.rim > 0 && !inRounded(size, l.radius, l.rim, x, y) ? RIM : PLATE;
	for (const r of l.rects)
		for (let y = r.y; y < r.y + r.h; y++) for (let x = r.x; x < r.x + r.w; x++) g[y * size + x] = r.c;
	return g;
}

export function toRgba(grid: Uint8Array): Uint8Array {
	const out = new Uint8Array(grid.length * 4);
	for (let i = 0; i < grid.length; i++) {
		const c = grid[i]!;
		out[i * 4] = PALETTE[c]![1];
		out[i * 4 + 1] = PALETTE[c]![2];
		out[i * 4 + 2] = PALETTE[c]![3];
		out[i * 4 + 3] = c === CLEAR ? 0 : 255;
	}
	return out;
}

export function render(size: number): Uint8Array {
	return toRgba(rasterize(layout(size)));
}

// The same layout as vector shapes: the plate and rim as rounded rects, then the tiles.
export function svgOf(l: Layout): string {
	const s = l.size;
	const out: string[] = [`<svg xmlns="http://www.w3.org/2000/svg" width="${s}" height="${s}" viewBox="0 0 ${s} ${s}">`];
	if (l.rim > 0) {
		out.push(`  <rect width="${s}" height="${s}" rx="${l.radius}" fill="${PALETTE[RIM]![0]}"/>`);
		const r = Math.max(0, l.radius - l.rim);
		out.push(`  <rect x="${l.rim}" y="${l.rim}" width="${s - 2 * l.rim}" height="${s - 2 * l.rim}" rx="${r}" fill="${PALETTE[PLATE]![0]}"/>`);
	} else {
		out.push(`  <rect width="${s}" height="${s}" rx="${l.radius}" fill="${PALETTE[PLATE]![0]}"/>`);
	}
	for (const r of l.rects) out.push(`  <rect x="${r.x}" y="${r.y}" width="${r.w}" height="${r.h}" fill="${PALETTE[r.c]![0]}"/>`);
	out.push("</svg>");
	return out.join("\n") + "\n";
}

// --- PNG (the only bytes this file needs to know: a signature, three chunks) -----

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const crcTable = new Uint32Array(256);
for (let n = 0; n < 256; n++) {
	let c = n;
	for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
	crcTable[n] = c >>> 0;
}
function crc32(data: Buffer): number {
	let c = 0xffffffff;
	for (let i = 0; i < data.length; i++) c = crcTable[(c ^ data[i]!) & 0xff]! ^ (c >>> 8);
	return (c ^ 0xffffffff) >>> 0;
}
function chunk(type: string, data: Buffer): Buffer {
	const out = Buffer.alloc(8 + data.length + 4);
	out.writeUInt32BE(data.length, 0);
	out.write(type, 4, "ascii");
	data.copy(out, 8);
	out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
	return out;
}

export function encodePng(width: number, height: number, rgba: Uint8Array): Buffer {
	if (rgba.length !== width * height * 4) throw new Error(`png: ${rgba.length} bytes for a ${width}x${height} image`);
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(width, 0);
	ihdr.writeUInt32BE(height, 4);
	ihdr[8] = 8; // bit depth
	ihdr[9] = 6; // colour type: RGBA
	const stride = width * 4;
	const raw = Buffer.alloc((stride + 1) * height);
	const pixels = Buffer.from(rgba.buffer, rgba.byteOffset, rgba.byteLength);
	for (let y = 0; y < height; y++) {
		raw[y * (stride + 1)] = 0; // filter: none
		pixels.subarray(y * stride, (y + 1) * stride).copy(raw, y * (stride + 1) + 1);
	}
	return Buffer.concat([PNG_SIGNATURE, chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw, { level: 9 })), chunk("IEND", Buffer.alloc(0))]);
}

// --- Windows icon: 128 and 256 stored as PNG (Windows reads both kinds), the small ones BMP
// for older loaders; a 128 px BMP alone is 64 KB, a lot for a favicon.

function bmpEntry(size: number, rgba: Uint8Array): Buffer {
	const maskRows = Math.ceil(size / 32) * 4; // bytes per mask row, padded to 32 bits
	const header = Buffer.alloc(40);
	header.writeUInt32LE(40, 0);
	header.writeInt32LE(size, 4);
	header.writeInt32LE(size * 2, 8); // XOR image plus AND mask
	header.writeUInt16LE(1, 12);
	header.writeUInt16LE(32, 14);
	header.writeUInt32LE(size * size * 4 + maskRows * size, 20);
	const xor = Buffer.alloc(size * size * 4);
	for (let y = 0; y < size; y++)
		for (let x = 0; x < size; x++) {
			const s = (y * size + x) * 4;
			const d = ((size - 1 - y) * size + x) * 4; // BMP rows run bottom up
			xor[d] = rgba[s + 2]!;
			xor[d + 1] = rgba[s + 1]!;
			xor[d + 2] = rgba[s]!;
			xor[d + 3] = rgba[s + 3]!;
		}
	// The AND mask repeats the alpha as one bit a pixel, for loaders that ignore alpha.
	const mask = Buffer.alloc(maskRows * size);
	for (let y = 0; y < size; y++)
		for (let x = 0; x < size; x++) {
			if (rgba[(y * size + x) * 4 + 3] !== 0) continue;
			const i = (size - 1 - y) * maskRows + (x >> 3);
			mask[i] = (mask[i] ?? 0) | (0x80 >> (x & 7));
		}
	return Buffer.concat([header, xor, mask]);
}

const PNG_ENTRY_SIZE = 128;

export function encodeIco(sizes: readonly number[]): Buffer {
	const header = Buffer.alloc(6 + 16 * sizes.length);
	header.writeUInt16LE(1, 2);
	header.writeUInt16LE(sizes.length, 4);
	const data: Buffer[] = [];
	let offset = header.length;
	sizes.forEach((size, i) => {
		if (size > 256) throw new Error(`ico: ${size} px is over the format's 256`);
		const o = 6 + i * 16; // the directory follows the 6-byte header
		header[o] = size === 256 ? 0 : size; // 0 means 256
		header[o + 1] = size === 256 ? 0 : size;
		header.writeUInt16LE(1, o + 4); // colour planes
		header.writeUInt16LE(32, o + 6); // bits per pixel
		const rgba = render(size);
		const body = size >= PNG_ENTRY_SIZE ? encodePng(size, size, rgba) : bmpEntry(size, rgba);
		header.writeUInt32LE(body.length, o + 8);
		header.writeUInt32LE(offset, o + 12);
		offset += body.length;
		data.push(body);
	});
	return Buffer.concat([header, ...data]);
}

// --- what lands in the repo --------------------------------------------------------

export const PNG_SIZES = [16, 24, 32, 48, 64, 128, 256, 512, 1024];
// Godot's Windows export copies 16, 32, 48, 64, 128 and 256 from the .ico into the exe and
// warns about any it lacks; 24 is the small taskbar icon at 150 % scaling.
export const ICO_SIZES = [16, 24, 32, 48, 64, 128, 256];
// The project icon: Godot imports the SVG at its own pixel size for the window icon,
// so it is laid out big enough for a dock or taskbar to scale down from.
export const SVG_SIZE = 256;

export function main(repo = root): string[] {
	writeFileSync(join(repo, "icon.svg"), svgOf(layout(SVG_SIZE)));
	mkdirSync(join(repo, "assets/logo"), { recursive: true });
	for (const size of PNG_SIZES) writeFileSync(join(repo, `assets/logo/icon-${size}.png`), encodePng(size, size, render(size)));
	writeFileSync(join(repo, "assets/logo/icon.ico"), encodeIco(ICO_SIZES));
	return ["icon.svg", "assets/logo/icon.ico", ...PNG_SIZES.map((s) => `assets/logo/icon-${s}.png`)];
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(import.meta.filename)) {
	for (const f of main()) console.log(f);
}

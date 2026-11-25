// The game logo, drawn in code: an S out of amber voxel tiles, one tile loose and
// falling, on the menu's dark plate. The design is a 32x32 grid (GRID) over a fixed
// palette, and everything this tool writes is a rendering of that grid, so the art
// is edited in one place:
//
//   node tools/icon.ts
//
//   icon.svg                  the project icon (config/icon in project.godot)
//   assets/logo/icon-<n>.png  the mark at a run of pixel sizes (the macOS app icon is 1024)
//   assets/logo/icon.ico      the Windows icon and the server web page's favicon
//
// No dependencies: the PNG is encoded here (zlib and a CRC table), the .ico around it.

import { mkdirSync, writeFileSync } from "node:fs";
import { deflateSync } from "node:zlib";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");

// The design grid: one integer pixel per cell, small enough to stay sharp at a tab icon.
export const GRID = 32;
const PLATE_RADIUS = 5;

// [hex, r, g, b]; outside the plate is transparent in the PNGs. The colours are the
// menu's own (core/main_menu.gd): its background for the plate, its accent for the S.
export const PALETTE: Array<[string, number, number, number]> = [
	["#000000", 0, 0, 0],
	["#121414", 18, 20, 20],
	["#d19e4c", 209, 158, 76],
	["#f7ba5a", 247, 186, 90],
	["#a37b3b", 163, 123, 59],
	// The loose tile is the same tile, in shadow: a step down, not another material (a
	// darker hue reads as a dead pixel).
	["#b28641", 178, 134, 65],
	["#c89649", 200, 150, 73],
	["#926e35", 146, 110, 53],
];

// The S as a 5x7 block letter of 4-pixel cells (its origin on the grid), with bold curves
// and no corner dots (the dotted one reads as a 5 or an 8 at a glance), and 1-pixel seams
// where two cells meet, so it reads as tiles. The base's bottom-right cell is loose: it
// sits over right and down from the crack it left, in the falling shades, and keeps a row
// of plate below it so it rests on the plate rather than over the edge.
const S_ROWS: number[][] = [[1, 2, 3], [0], [0], [1, 2, 3], [4], [4], [1, 2, 3]];
const CELL = 4;
const S_ORIGIN: [number, number] = [6, 2];
const LOOSE = { row: 6, col: 3, dx: 2, dy: 1 };

function inPlate(x: number, y: number): boolean {
	const r = PLATE_RADIUS;
	const top = y < r;
	const bottom = y >= GRID - r;
	if (!top && !bottom) return true;
	if (x >= r && x < GRID - r) return true;
	const cx = x < r ? r : GRID - 1 - r;
	const cy = top ? r : GRID - 1 - r;
	return (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r;
}

// One tile: the base colour with a lit top and left edge and a shaded bottom and right.
function tile(
	g: Uint8Array,
	row: number,
	col: number,
	base: number,
	light: number,
	dark: number,
	dx: number,
	dy: number,
): void {
	const x0 = S_ORIGIN[0] + col * CELL + dx;
	const y0 = S_ORIGIN[1] + row * CELL + dy;
	for (let y = 0; y < CELL; y++)
		for (let x = 0; x < CELL; x++) g[(y0 + y) * GRID + x0 + x] = base;
	for (let y = 0; y < CELL; y++) g[(y0 + y) * GRID + x0 + CELL - 1] = dark;
	for (let y = 0; y < CELL; y++) g[(y0 + y) * GRID + x0] = light;
	for (let x = 0; x < CELL; x++) g[y0 * GRID + x0 + x] = light;
	for (let x = 0; x < CELL; x++) g[(y0 + CELL - 1) * GRID + x0 + x] = dark;
}

function filled(row: number, col: number): boolean {
	const r = S_ROWS[row];
	return r !== undefined && r.includes(col) && !(row === LOOSE.row && col === LOOSE.col);
}

export function buildGrid(): Uint8Array {
	const g = new Uint8Array(GRID * GRID);
	for (let y = 0; y < GRID; y++) for (let x = 0; x < GRID; x++) if (inPlate(x, y)) g[y * GRID + x] = 1;
	for (let row = 0; row < S_ROWS.length; row++)
		for (const col of S_ROWS[row]!) if (filled(row, col)) tile(g, row, col, 2, 3, 4, 0, 0);
	// Seams where two tiles meet: the plate shows through between them.
	for (let row = 0; row < S_ROWS.length; row++)
		for (const col of S_ROWS[row]!) {
			if (!filled(row, col)) continue;
			const x0 = S_ORIGIN[0] + col * CELL;
			const y0 = S_ORIGIN[1] + row * CELL;
			if (filled(row, col + 1)) for (let y = 0; y < CELL; y++) g[(y0 + y) * GRID + x0 + CELL - 1] = 1;
			if (filled(row + 1, col)) for (let x = 0; x < CELL; x++) g[(y0 + CELL - 1) * GRID + x0 + x] = 1;
		}
	// The loose tile lands on the plate, so it is painted last.
	tile(g, LOOSE.row, LOOSE.col, 5, 6, 7, LOOSE.dx, LOOSE.dy);
	return g;
}

// The grid at any pixel size: nearest-neighbour, so a tile edge never blurs.
export function render(size: number, grid: Uint8Array): Uint8Array {
	const out = new Uint8Array(size * size * 4);
	const k = GRID / size;
	for (let y = 0; y < size; y++) {
		const gy = Math.min(GRID - 1, Math.floor((y + 0.5) * k));
		for (let x = 0; x < size; x++) {
			const gx = Math.min(GRID - 1, Math.floor((x + 0.5) * k));
			const c = grid[gy * GRID + gx]!;
			const o = (y * size + x) * 4;
			out[o] = PALETTE[c]![1];
			out[o + 1] = PALETTE[c]![2];
			out[o + 2] = PALETTE[c]![3];
			out[o + 3] = c === 0 ? 0 : 255;
		}
	}
	return out;
}

// A flat grid to SVG: one rect per colour run in each row (Godot's importer handles it).
export function svgOf(grid: Uint8Array): string {
	const rows: string[] = [`<svg xmlns="http://www.w3.org/2000/svg" width="${GRID}" height="${GRID}" viewBox="0 0 ${GRID} ${GRID}">`];
	for (let y = 0; y < GRID; y++) {
		let x = 0;
		while (x < GRID) {
			const c = grid[y * GRID + x]!;
			let x1 = x + 1;
			while (x1 < GRID && grid[y * GRID + x1]! === c) x1++;
			if (c !== 0) rows.push(`  <rect x="${x}" y="${y}" width="${x1 - x}" height="1" fill="${PALETTE[c]![0]}"/>`);
			x = x1;
		}
	}
	rows.push("</svg>");
	return rows.join("\n") + "\n";
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

export function encodePng(size: number, rgba: Uint8Array): Buffer {
	if (rgba.length !== size * size * 4) throw new Error(`png: ${rgba.length} bytes for a ${size}x${size} image`);
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(size, 0);
	ihdr.writeUInt32BE(size, 4);
	ihdr[8] = 8; // bit depth
	ihdr[9] = 6; // colour type: RGBA
	const raw = Buffer.alloc((size * 4 + 1) * size);
	const pixels = Buffer.from(rgba.buffer, rgba.byteOffset, rgba.byteLength);
	for (let y = 0; y < size; y++) {
		raw[y * (size * 4 + 1)] = 0; // filter: none
		pixels.subarray(y * size * 4, (y + 1) * size * 4).copy(raw, y * (size * 4 + 1) + 1);
	}
	return Buffer.concat([PNG_SIGNATURE, chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw, { level: 9 })), chunk("IEND", Buffer.alloc(0))]);
}

// --- Windows icon: 256 is stored as a PNG (as Windows expects); the rest BMP -----

function bmpEntry(size: number, rgba: Uint8Array): Buffer {
	const maskRows = Math.ceil(size / 32) * 4;
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
	return Buffer.concat([header, xor, Buffer.alloc(maskRows * size)]);
}

export function encodeIco(entries: Array<{ size: number; png: Buffer | null; rgba: Uint8Array }>): Buffer {
	const header = Buffer.alloc(6 + 16 * entries.length);
	header.writeUInt16LE(1, 2);
	header.writeUInt16LE(entries.length, 4);
	const data: Buffer[] = [];
	let offset = header.length;
	entries.forEach((e, i) => {
		const o = 6 + i * 16; // the directory follows the 6-byte header
		header[o] = e.size === 256 ? 0 : e.size; // 0 means 256
		header[o + 1] = e.size === 256 ? 0 : e.size;
		const body = e.size === 256 ? e.png ?? bmpEntry(e.size, e.rgba) : bmpEntry(e.size, e.rgba);
		header.writeUInt32LE(body.length, o + 8);
		header.writeUInt32LE(offset, o + 12);
		offset += body.length;
		data.push(body);
	});
	return Buffer.concat([header, ...data]);
}

// --- what lands in the repo --------------------------------------------------------

const SIZES = [16, 24, 32, 48, 64, 128, 256, 512, 1024];

export function main(repow = root): string[] {
	const grid = buildGrid();
	const svg = svgOf(grid);
	writeFileSync(join(repow, "icon.svg"), svg);
	mkdirSync(join(repow, "assets/logo"), { recursive: true });
	const png256 = encodePng(256, render(256, grid));
	for (const size of SIZES) {
		const png = size === 256 ? png256 : encodePng(size, render(size, grid));
		writeFileSync(join(repow, `assets/logo/icon-${size}.png`), png);
	}
	const ico = encodeIco([
		{ size: 16, png: null, rgba: render(16, grid) },
		{ size: 24, png: null, rgba: render(24, grid) },
		{ size: 32, png: null, rgba: render(32, grid) },
		{ size: 48, png: null, rgba: render(48, grid) },
		{ size: 256, png: png256, rgba: render(256, grid) },
	]);
	writeFileSync(join(repow, "assets/logo/icon.ico"), ico);
	return ["icon.svg", "assets/logo/icon.ico", ...SIZES.map((s) => `assets/logo/icon-${s}.png`)];
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(import.meta.filename)) {
	for (const f of main()) console.log(f);
}

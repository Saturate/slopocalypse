// The logo is a grid, not a file: the art must stay an S with its one loose tile, and
// the PNG and ICO bytes must be what a loader would decode back.  node --test tools/

import test from "node:test";
import assert from "node:assert";
import { inflateSync } from "node:zlib";

import { GRID, PALETTE, buildGrid, encodeIco, encodePng, render, svgOf } from "./icon.ts";

const at = (g: Uint8Array, x: number, y: number): number => g[y * GRID + x]!;

test("the grid is a rounded plate holding a whole S with one loose tile", () => {
	const g = buildGrid();
	// The plate: transparent at the very corner, rounded in, solid along the edge.
	assert.equal(at(g, 0, 0), 0, "the plate corner is cut");
	assert.equal(at(g, 4, 0), 0, "the rounding cuts the plate back");
	assert.equal(at(g, 5, 0), 1, "the plate edge is straight here");
	assert.equal(at(g, 16, 0), 1, "the plate is full across the top");
	// The S: 13 tiles of 16 pixels (12 in place plus the loose one), minus a seam
	// (4 pixels) where two tiles meet: five horizontal (the base's last is a gap, where
	// the loose tile slid from) and two vertical.
	let s = 0;
	for (const c of g) if (c !== 0 && c !== 1) s++;
	assert.equal(s, 13 * 16 - 7 * 4);
	// The loose tile landed over right and down, in its own shades, a row above the edge...
	assert.equal(at(g, 20, 27), 6, "the loose tile's lit corner");
	assert.equal(at(g, 21, 28), 5, "the loose tile's body");
	assert.equal(at(g, 23, 30), 7, "the loose tile's shaded corner");
	assert.equal(at(g, 21, 31), 1, "plate still runs under it");
	// ...and the hole it left is plate, not S.
	assert.equal(at(g, 18, 26), 1, "the base's corner tile is gone");
	assert.equal(at(g, 19, 27), 1, "the crack beside it is plate");
	// The letter's strokes: the base is whole except its lost corner, the middle bar is in.
	assert.equal(at(g, 12, 27), 2, "the base still runs under its gap");
	assert.equal(at(g, 12, 15), 2, "the middle bar");
	// The svg is lossless over the grid: laying its rects back out gives the same pixels.
	const svg = svgOf(g);
	assert.ok(svg.startsWith(`<svg xmlns="http://www.w3.org/2000/svg" width="${GRID}" height="${GRID}"`) && svg.endsWith("</svg>\n"));
	const byHex = new Map(PALETTE.map((p, i) => [p[0], i]));
	const back = new Uint8Array(GRID * GRID);
	for (const m of svg.matchAll(/<rect x="(\d+)" y="(\d+)" width="(\d+)" height="1" fill="(#[0-9a-f]{6})"\/>/g)) {
		const x = Number(m[1]), y = Number(m[2]), w = Number(m[3]);
		const c = byHex.get(m[4]!)!;
		for (let xi = x; xi < x + w; xi++) back[y * GRID + xi] = c;
	}
	assert.deepEqual([...back], [...g], "the svg's rects rebuild the grid");
});

test("the png is the grid, at its claimed size", () => {
	const g = buildGrid();
	const png = encodePng(32, render(32, g));
	assert.deepEqual([...png.subarray(0, 8)], [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
	assert.equal(png.readUInt32BE(16), 32, "the width in the header");
	assert.equal(png.readUInt32BE(20), 32, "the height in the header");
	assert.equal(png[24], 8, "8-bit");
	assert.equal(png[25], 6, "RGBA");
	// Walk the chunks to the IDAT and decode it back: one filter byte per row, then pixels.
	let p = 8;
	let idat = Buffer.alloc(0);
	while (p < png.length) {
		const len = png.readUInt32BE(p);
		const type = png.toString("ascii", p + 4, p + 8);
		if (type === "IDAT") idat = Buffer.concat([idat, png.subarray(p + 8, p + 8 + len)]);
		p += 12 + len;
	}
	const raw = inflateSync(idat);
	assert.equal(raw.length, 32 * (32 * 4 + 1));
	const check = (x: number, y: number): void => {
		const c = at(g, x, y);
		const pal = PALETTE[c]!;
		const o = y * (32 * 4 + 1) + x * 4 + 1; // raw is filter byte + row, per row
		assert.deepEqual([...raw.subarray(o, o + 4)], [pal[1], pal[2], pal[3], c === 0 ? 0 : 255], `pixel ${x},${y}`);
	};
	check(0, 0); // outside the plate: transparent
	check(16, 0); // plate
	check(12, 15); // the S
	check(21, 29); // the loose tile
});

test("the ico carries one entry per size, decodable at the small end", () => {
	const g = buildGrid();
	const png256 = encodePng(256, render(256, g));
	const ico = encodeIco([
		{ size: 16, png: null, rgba: render(16, g) },
		{ size: 24, png: null, rgba: render(24, g) },
		{ size: 32, png: null, rgba: render(32, g) },
		{ size: 48, png: null, rgba: render(48, g) },
		{ size: 256, png: png256, rgba: render(256, g) },
	]);
	assert.equal(ico.readUInt16LE(2), 1, "an icon, not a cursor");
	assert.equal(ico.readUInt16LE(4), 5);
	for (let i = 0; i < 5; i++) {
		const size = [16, 24, 32, 48, 256][i]!;
		const o = 6 + i * 16;
		assert.equal(ico[o], size === 256 ? 0 : size, "the entry names its size; 0 means 256");
		assert.equal(ico[o + 1], ico[o], "width and height match");
		const length = ico.readUInt32LE(o + 8);
		const offset = ico.readUInt32LE(o + 12);
		assert.ok(offset + length <= ico.length, `entry ${i}'s data fits in the file`);
		if (size === 256) {
			// The big entry is the png.
			assert.equal(length, png256.length);
			assert.deepEqual([...ico.subarray(offset, offset + 8)], [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
		} else {
			// The small ones are 32-bpp BMPs: the header says so, data and AND mask counted.
			assert.equal(ico.readUInt32LE(offset), 40, "the BMP header");
			assert.equal(ico.readInt32LE(offset + 4), size);
			assert.equal(ico.readInt32LE(offset + 8), size * 2, "the header counts the AND mask too");
			assert.equal(ico.readUInt16LE(offset + 14), 32);
			assert.equal(length, 40 + size * size * 4 + Math.ceil(size / 32) * 4 * size, "the entry data is whole");
		}
	}
	// A small entry's pixels are the grid, bottom up: (24,24) samples grid (16,16), the S's base.
	const e48 = ico.readUInt32LE(6 + 3 * 16 + 12);
	const d = e48 + 40 + ((48 - 1 - 24) * 48 + 24) * 4;
	assert.deepEqual([...ico.subarray(d, d + 4)], [76, 158, 209, 255], "a BGRA pixel of the S");
});

test("the generated bytes are stable", () => {
	const twice = (): string => {
		const g = buildGrid();
		return Buffer.from(encodePng(64, render(64, g))).toString("hex") + svgOf(g);
	};
	assert.equal(twice(), twice());
});

// The logo is a layout, not a file: the art must stay a whole S at every size, and the
// PNG and ICO bytes must be what a loader would decode back.  node --test tools/

import test from "node:test";
import assert from "node:assert";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { inflateSync } from "node:zlib";

import { CLEAR, ICO_SIZES, PALETTE, PLATE, PNG_SIZES, RIM, S_ROWS, SVG_SIZE, TILE, TILE_LIT, TILE_SHADE, encodeIco, encodePng, layout, rasterize, render, svgOf } from "./icon.ts";

const root = resolve(import.meta.dirname, "..");
const isTile = (c: number): boolean => c === TILE || c === TILE_LIT || c === TILE_SHADE;

// Reads the image back cell by cell: is the middle of each letter cell amber?
function letterAt(size: number): string[] {
	const l = layout(size);
	const g = rasterize(l);
	const ox = Math.floor((size - 5 * l.pitch) / 2);
	const oy = Math.floor((size - 7 * l.pitch) / 2);
	const rows: string[] = [];
	for (let row = 0; row < 7; row++) {
		let s = "";
		for (let col = 0; col < 5; col++) {
			const x = ox + col * l.pitch + Math.floor(l.pitch / 2);
			const y = oy + row * l.pitch + Math.floor(l.pitch / 2);
			s += isTile(g[y * size + x]!) ? "X" : ".";
		}
		rows.push(s);
	}
	return rows;
}

test("every size draws the whole S, ends and all, inside the plate", () => {
	assert.equal(S_ROWS[1]![4], "X", "the top-right end");
	assert.equal(S_ROWS[5]![0], "X", "the bottom-left end");
	for (const size of [...PNG_SIZES, 20, 40]) {
		assert.deepEqual(letterAt(size), [...S_ROWS], `the S at ${size} px`);
		const g = rasterize(layout(size));
		assert.equal(g[0], CLEAR, `${size} px: the plate's corner is rounded off`);
		// No tile on the outermost ring of pixels: the letter keeps a margin of plate.
		for (let i = 0; i < size; i++)
			for (const p of [i, (size - 1) * size + i, i * size, i * size + size - 1])
				assert.ok(!isTile(g[p]!), `${size} px: a tile on the edge at pixel ${p}`);
	}
});

test("strokes are solid bars, with grooves between tiles only at big sizes", () => {
	// 16 px: the tiles are the plain accent, so the letter is one solid shape; the rim
	// still outlines the plate on a dark background.
	const g16 = rasterize(layout(16));
	assert.ok(g16.every((c) => c !== TILE_LIT && c !== TILE_SHADE), "16 px has no bevel pixels");
	assert.equal(g16[8 * 16], RIM, "a rim outlines the plate at 16 px");
	// 32 and 64 px: the top bar is lit along its top and runs unbroken from tile to tile.
	for (const size of [32, 64]) {
		const l = layout(size);
		assert.ok(!l.grooved && l.bevel > 0);
		const g = rasterize(l);
		const ox = Math.floor((size - 5 * l.pitch) / 2);
		const oy = Math.floor((size - 7 * l.pitch) / 2);
		const top = [...g.subarray(oy * size + ox + l.pitch, oy * size + ox + 4 * l.pitch)];
		assert.ok(top.every((c) => c === TILE_LIT), `${size} px: the bar's lit top edge is unbroken`);
		const y = oy + Math.floor(l.pitch / 2);
		const mid = [...g.subarray(y * size + ox + l.pitch + l.bevel, y * size + ox + 4 * l.pitch - l.bevel)];
		assert.ok(mid.every((c) => c === TILE), `${size} px: no edge between tiles inside a bar`);
	}
	// 256 px: a shaded edge then a lit one where two tiles of the top bar meet, and never
	// plate between them.
	const l256 = layout(256);
	assert.ok(l256.grooved && l256.bevel > 0);
	const g256 = rasterize(l256);
	const ox = Math.floor((256 - 5 * l256.pitch) / 2);
	const y = Math.floor((256 - 7 * l256.pitch) / 2) + Math.floor(l256.pitch / 2);
	const meet = ox + 2 * l256.pitch;
	assert.equal(g256[y * 256 + meet - 1], TILE_SHADE, "the groove's shaded side");
	assert.equal(g256[y * 256 + meet], TILE_LIT, "the groove's lit side");
	for (let x = ox + l256.pitch; x < ox + 4 * l256.pitch; x++) assert.ok(isTile(g256[y * 256 + x]!), `no plate in the bar at x ${x}`);
});

test("the svg holds the same plate and tiles as the pixels", () => {
	const l = layout(SVG_SIZE);
	const s = SVG_SIZE;
	const svg = svgOf(l);
	assert.ok(svg.startsWith(`<svg xmlns="http://www.w3.org/2000/svg" width="${s}" height="${s}"`) && svg.endsWith("</svg>\n"));
	assert.ok(svg.includes(`<rect width="${s}" height="${s}" rx="${l.radius}" fill="${PALETTE[RIM]![0]}"/>`), "the rim");
	const inner = s - 2 * l.rim;
	assert.ok(svg.includes(`<rect x="${l.rim}" y="${l.rim}" width="${inner}" height="${inner}" rx="${l.radius - l.rim}" fill="${PALETTE[PLATE]![0]}"/>`), "the plate inside it");
	const tiles = [...svg.matchAll(/<rect x="(\d+)" y="(\d+)" width="(\d+)" height="(\d+)" fill="(#[0-9a-f]{6})"\/>/g)];
	assert.equal(tiles.length, l.rects.length);
	const g = rasterize(l);
	const byHex = new Map(PALETTE.map((p, i) => [p[0], i]));
	// Laying the rects out in order gives the same tiles as the raster.
	const back = new Uint8Array(s * s);
	for (const m of tiles) {
		const [x, y, w, h] = [Number(m[1]), Number(m[2]), Number(m[3]), Number(m[4])];
		for (let yi = y; yi < y + h; yi++) for (let xi = x; xi < x + w; xi++) back[yi * s + xi] = byHex.get(m[5]!)!;
	}
	for (let i = 0; i < g.length; i++) if (isTile(g[i]!) || isTile(back[i]!)) assert.equal(back[i], g[i], `pixel ${i}`);
});

test("the palette is the UI's own", () => {
	const ui = readFileSync(join(root, "core/ui/ui_palette.gd"), "utf8");
	const hex = (name: string): string => `#${ui.match(new RegExp(`const ${name} := Color\\("([0-9a-f]{6})"\\)`))?.[1]}`;
	assert.equal(PALETTE[PLATE]![0], hex("BACKGROUND"));
	assert.equal(PALETTE[RIM]![0], hex("STEEL"));
	assert.equal(PALETTE[TILE]![0], hex("ACCENT"));
	for (const [h, r, g, b] of PALETTE) assert.equal(h, `#${[r, g, b].map((v) => v.toString(16).padStart(2, "0")).join("")}`);
});

test("the png is the image, at its claimed size", () => {
	const rgba = render(32);
	const png = encodePng(32, 32, rgba);
	assert.deepEqual([...png.subarray(0, 8)], [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
	assert.equal(png.readUInt32BE(16), 32, "the width in the header");
	assert.equal(png.readUInt32BE(20), 32, "the height in the header");
	assert.equal(png[24], 8, "8-bit");
	assert.equal(png[25], 6, "RGBA");
	let p = 8;
	let idat = Buffer.alloc(0);
	while (p < png.length) {
		const len = png.readUInt32BE(p);
		if (png.toString("ascii", p + 4, p + 8) === "IDAT") idat = Buffer.concat([idat, png.subarray(p + 8, p + 8 + len)]);
		p += 12 + len;
	}
	const raw = inflateSync(idat);
	assert.equal(raw.length, 32 * (32 * 4 + 1));
	for (let y = 0; y < 32; y++) {
		assert.equal(raw[y * (32 * 4 + 1)], 0, "filter byte");
		assert.deepEqual([...raw.subarray(y * (32 * 4 + 1) + 1, (y + 1) * (32 * 4 + 1))], [...rgba.subarray(y * 128, (y + 1) * 128)], `row ${y}`);
	}
	assert.equal(rgba[3], 0, "outside the plate is transparent");
});

test("the ico carries one entry per size, decodable at the small end", () => {
	const ico = encodeIco(ICO_SIZES);
	assert.equal(ico.readUInt16LE(2), 1, "an icon, not a cursor");
	assert.equal(ico.readUInt16LE(4), ICO_SIZES.length);
	ICO_SIZES.forEach((size, i) => {
		const o = 6 + i * 16;
		assert.equal(ico[o], size === 256 ? 0 : size, "the entry names its size; 0 means 256");
		assert.equal(ico[o + 1], ico[o], "width and height match");
		assert.equal(ico.readUInt16LE(o + 6), 32, "32 bits per pixel");
		const length = ico.readUInt32LE(o + 8);
		const offset = ico.readUInt32LE(o + 12);
		assert.ok(offset + length <= ico.length, `entry ${i}'s data fits in the file`);
		if (size >= 128) {
			assert.deepEqual([...ico.subarray(offset, offset + 8)], [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], "the big entries are png");
		} else {
			assert.equal(ico.readUInt32LE(offset), 40, "the BMP header");
			assert.equal(ico.readInt32LE(offset + 4), size);
			assert.equal(ico.readInt32LE(offset + 8), size * 2, "the header counts the AND mask too");
			assert.equal(length, 40 + size * size * 4 + Math.ceil(size / 32) * 4 * size, "the entry data is whole");
			// The AND mask marks the cut plate corner (bottom row first, so the top row is last).
			const mask = offset + 40 + size * size * 4;
			const rowBytes = Math.ceil(size / 32) * 4;
			assert.equal(ico[mask + (size - 1) * rowBytes]! & 0x80, 0x80, "the top-left pixel is masked");
			assert.equal(ico[mask + (size >> 1) * rowBytes + (size >> 4)]! & (0x80 >> ((size >> 1) & 7)), 0, "the middle is not");
		}
	});
	// A small entry's pixels are the image, bottom up and BGRA.
	const i48 = ICO_SIZES.indexOf(48);
	const e48 = ico.readUInt32LE(6 + i48 * 16 + 12);
	const rgba = render(48);
	const points: Array<[number, number]> = [[0, 0], [24, 24], [20, 5]];
	for (const [x, y] of points) {
		const s = (y * 48 + x) * 4;
		const d = e48 + 40 + ((48 - 1 - y) * 48 + x) * 4;
		assert.deepEqual([...ico.subarray(d, d + 4)], [rgba[s + 2], rgba[s + 1], rgba[s], rgba[s + 3]], `pixel ${x},${y}`);
	}
});

// A PNG's IDAT inflated: the filter bytes and pixels, whatever deflate wrote them
// (zlib builds differ between Node versions, so the compressed bytes may not match).
function pngRaw(png: Buffer): Buffer {
	let p = 8;
	const idat: Buffer[] = [];
	while (p < png.length) {
		const len = png.readUInt32BE(p);
		if (png.toString("ascii", p + 4, p + 8) === "IDAT") idat.push(png.subarray(p + 8, p + 8 + len));
		p += 12 + len;
	}
	return inflateSync(Buffer.concat(idat));
}

const PNG_MAGIC = Buffer.from([0x89, 0x50, 0x4e, 0x47]);

test("the files in the repo are what the generator writes", () => {
	for (const size of PNG_SIZES) {
		const file = readFileSync(join(root, `assets/logo/icon-${size}.png`));
		// PNGs live in Git LFS, and a checkout without LFS has only the pointer.
		if (file.subarray(0, 24).toString("ascii") === "version https://git-lfs.") continue;
		const want = encodePng(size, size, render(size));
		assert.ok(file.subarray(0, 33).equals(want.subarray(0, 33)), `icon-${size}.png header is stale: node tools/icon.ts`);
		assert.ok(pngRaw(file).equals(pngRaw(want)), `icon-${size}.png is stale: node tools/icon.ts`);
	}
	const ico = readFileSync(join(root, "assets/logo/icon.ico"));
	const want = encodeIco(ICO_SIZES);
	assert.equal(ico.readUInt16LE(4), want.readUInt16LE(4), "icon.ico is stale: node tools/icon.ts");
	for (let i = 0; i < want.readUInt16LE(4); i++) {
		const o = 6 + i * 16;
		const entry = (b: Buffer): Buffer => b.subarray(b.readUInt32LE(o + 12), b.readUInt32LE(o + 12) + b.readUInt32LE(o + 8));
		const [have, expect] = [entry(ico), entry(want)];
		const same = expect.subarray(0, 4).equals(PNG_MAGIC) ? have.subarray(0, 4).equals(PNG_MAGIC) && pngRaw(have).equals(pngRaw(expect)) : have.equals(expect);
		assert.ok(ico[o] === want[o] && same, `icon.ico entry ${i} is stale: node tools/icon.ts`);
	}
	assert.equal(readFileSync(join(root, "icon.svg"), "utf8"), svgOf(layout(SVG_SIZE)), "icon.svg is stale: node tools/icon.ts");
});

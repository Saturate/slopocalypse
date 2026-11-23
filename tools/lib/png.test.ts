import assert from "node:assert/strict";
import { test } from "node:test";
import { deflateSync } from "node:zlib";
import { brighterPixels, decodePng, encodePng, findColour, meanLuma, parseColour, type Image } from "./png.ts";

function solid(width: number, height: number, rgba: readonly [number, number, number, number]): Image {
	const data = new Uint8Array(width * height * 4);
	for (let i = 0; i < width * height; i++) data.set(rgba, i * 4);
	return { width, height, data };
}

test("an encoded image decodes to the same pixels", () => {
	const img = solid(5, 3, [10, 20, 30, 255]);
	img.data.set([200, 100, 50, 128], (1 * 5 + 2) * 4);
	assert.deepEqual(decodePng(encodePng(img)), img);
});

// A 3x2 RGB PNG whose rows use the Sub and Paeth filters, as Godot's encoder may write them.
test("filtered RGB rows are undone", () => {
	const head = Buffer.alloc(13);
	head.writeUInt32BE(3, 0);
	head.writeUInt32BE(2, 4);
	head.set([8, 2, 0, 0, 0], 8);
	// Row 0, Sub: each byte is the difference from the pixel to its left.
	const row0 = [1, 10, 20, 30, 5, 5, 5, 5, 5, 5];
	// Row 1, Paeth against row 0 (10,20,30 15,25,35 20,30,40): the deltas below give 11,21,31 ...
	const row1 = [4, 1, 1, 1, 1, 1, 1, 1, 1, 1];
	const raw = deflateSync(Buffer.from([...row0, ...row1]));
	const chunk = (type: string, body: Buffer): Buffer => {
		const len = Buffer.alloc(4);
		len.writeUInt32BE(body.length, 0);
		return Buffer.concat([len, Buffer.from(type, "ascii"), body, Buffer.alloc(4)]);
	};
	const png = Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", head), chunk("IDAT", raw), chunk("IEND", Buffer.alloc(0))]);
	const img = decodePng(png);
	assert.deepEqual([...img.data.subarray(0, 12)], [10, 20, 30, 255, 15, 25, 35, 255, 20, 30, 40, 255]);
	assert.deepEqual([...img.data.subarray(12, 24)], [11, 21, 31, 255, 16, 26, 36, 255, 21, 31, 41, 255]);
});

test("anything Godot does not write is refused", () => {
	assert.throws(() => decodePng(Buffer.from("not a png")), /not a PNG/);
});

test("a colour is found in a region and missed outside it", () => {
	const img = solid(10, 10, [0, 0, 0, 255]);
	img.data.set([95, 182, 255, 255], (8 * 10 + 8) * 4);
	const blue = parseColour("#5fb6ff");
	const all = findColour(img, blue, 10);
	assert.equal(all.count, 1);
	assert.deepEqual(all.centre, [0.8, 0.8]);
	const left = findColour(img, blue, 10, { x: 0, y: 0, w: 0.5, h: 1 });
	assert.equal(left.count, 0);
	assert.equal(left.centre, undefined);
	assert.ok(left.distance > 200);
	assert.throws(() => parseColour("blue"), /#rrggbb/);
});

test("brightness and what got brighter", () => {
	const dark = solid(4, 4, [0, 0, 0, 255]);
	const lit = solid(4, 4, [0, 0, 0, 255]);
	lit.data.set([255, 255, 255, 255], 0);
	assert.equal(meanLuma(dark), 0);
	assert.ok(Math.abs(meanLuma(lit) - 255 / 16) < 0.01);
	assert.equal(brighterPixels(dark, lit, 60), 1);
	assert.equal(brighterPixels(lit, dark, 60), 0);
	assert.equal(brighterPixels(dark, lit, 60, { x: 0.5, y: 0.5, w: 0.5, h: 0.5 }), 0);
	assert.throws(() => brighterPixels(dark, solid(2, 2, [0, 0, 0, 255]), 60), /differ in size/);
});

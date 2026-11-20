import { test } from "node:test";
import assert from "node:assert/strict";
import { cacheKey, parseRender, recipeFile } from "./map-viewer.ts";

test("a render request defaults to grassland seed 1 at 512 pixels with every layer but the remoteness tint", () => {
	assert.deepEqual(parseRender(new URLSearchParams()), { map: "grassland", seed: 1, pixels: 512, layers: ["zones", "settlements", "roads", "earthworks", "sites"] });
});

test("a render request reads its parameters and drops repeated layers", () => {
	const r = parseRender(new URLSearchParams("map=mixed&seed=42&pixels=256&layers=roads,roads,zones"));
	assert.deepEqual(r, { map: "mixed", seed: 42, pixels: 256, layers: ["roads", "zones"] });
});

test("a render request refuses paths, bad numbers and unknown layers", () => {
	assert.throws(() => parseRender(new URLSearchParams("map=../../etc")));
	assert.throws(() => parseRender(new URLSearchParams("seed=-1")));
	assert.throws(() => parseRender(new URLSearchParams("pixels=10")));
	assert.throws(() => parseRender(new URLSearchParams("layers=bombs")));
});

test("the cache key changes with the recipe text and not with the layer order", () => {
	const a = parseRender(new URLSearchParams("layers=roads,zones"));
	const b = parseRender(new URLSearchParams("layers=zones,roads"));
	assert.equal(cacheKey(a, "{}"), cacheKey(b, "{}"));
	assert.notEqual(cacheKey(a, '{"relief": 1}'), cacheKey(a, '{"relief": 2}'));
});

test("recipes live in the world module", () => {
	assert.equal(recipeFile("grassland"), "modules/world/data/maps/grassland.json");
});

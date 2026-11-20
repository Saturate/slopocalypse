import { test } from "node:test";
import assert from "node:assert/strict";
import { parsePreviewArgs, recipePath } from "./map-preview.ts";

test("map preview defaults to the grassland recipe, seed 1, 512 pixels, into build/maps", () => {
	assert.deepEqual(parsePreviewArgs([]), { map: "grassland", seed: 1, out: "build/maps/grassland-1.png", pixels: 512 });
});

test("map preview reads its flags", () => {
	assert.deepEqual(parsePreviewArgs(["--map=mixed", "--seed=42", "--pixels=256", "--out=x.png"]), { map: "mixed", seed: 42, out: "x.png", pixels: 256 });
});

test("map preview refuses a recipe name that is a path, and bad numbers", () => {
	assert.throws(() => parsePreviewArgs(["--map=../secrets"]));
	assert.throws(() => parsePreviewArgs(["--seed=1.5"]));
	assert.throws(() => parsePreviewArgs(["--pixels=8"]));
});

test("recipes live in the world module's maps folder", () => {
	assert.equal(recipePath("grassland"), "res://modules/world/data/maps/grassland.json");
});

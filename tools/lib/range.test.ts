import { test } from "node:test";
import assert from "node:assert/strict";
import { rangeFlags } from "./range.ts";

test("the range's flags come from its data, or none", () => {
	assert.equal(rangeFlags('{"flags": "drones:off,enemies:off"}'), "drones:off,enemies:off");
	assert.equal(rangeFlags('{"type": {}}'), undefined);
	assert.equal(rangeFlags('{"flags": 3}'), undefined);
});

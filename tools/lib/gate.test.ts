import assert from "node:assert/strict";
import { test } from "node:test";
import { retryOnce, type StepResult } from "./gate.ts";

test("a step that passes runs once", async () => {
	let runs = 0;
	const r = await retryOnce(async (): Promise<StepResult> => {
		runs++;
		return { ok: true, detail: "clean" };
	});
	assert.equal(runs, 1);
	assert.deepEqual(r, { ok: true, detail: "clean" });
});

test("a step that fails once and then passes passes, and says it was retried", async () => {
	let runs = 0;
	const r = await retryOnce(async (): Promise<StepResult> => {
		runs++;
		return runs === 1 ? { ok: false, detail: "import exit -1" } : { ok: true, detail: "clean" };
	});
	assert.equal(runs, 2);
	assert.equal(r.ok, true);
	assert.match(r.detail, /retried/);
	assert.match(r.detail, /import exit -1/);
});

test("a step that fails twice fails with the second result", async () => {
	let runs = 0;
	const r = await retryOnce(async (): Promise<StepResult> => {
		runs++;
		return { ok: false, detail: `failure ${runs}` };
	});
	assert.equal(runs, 2);
	assert.deepEqual(r, { ok: false, detail: "failure 2" });
});

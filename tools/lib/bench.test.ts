import assert from "node:assert/strict";
import { test } from "node:test";
import { compare, parsePerfLog, summarise, type Summary } from "./bench.ts";

const log = [
	'{"t":1,"frames":60,"frame_ms_mean":30,"frame_ms_p95":50,"frame_ms_max":90,"physics_ms":2,"memory_mb":100,"nodes":500}',
	'{"t":11,"spike_ms":70,"nodes":900}',
	'{"t":12,"frames":60,"frame_ms_mean":10,"frame_ms_p95":14,"frame_ms_max":20,"physics_ms":1,"memory_mb":200,"nodes":900}',
	'{"t":13,"frames":60,"frame_ms_mean":12,"frame_ms_p95":16,"frame_ms_max":40,"physics_ms":3,"memory_mb":210,"nodes":950}',
	'{"t":14,"frames":6',
].join("\n");

test("samples after the warm-up summarise; spikes and cut-off lines are skipped", () => {
	const s = summarise(parsePerfLog(log), 10);
	assert.deepEqual(s, { samples: 2, frame_ms_mean: 11, frame_ms_p95: 15, frame_ms_worst: 40, physics_ms: 2, gpu_ms: 0, memory_mb: 210, nodes: 950 });
});

const base: Summary = { samples: 50, frame_ms_mean: 10, frame_ms_p95: 15, frame_ms_worst: 40, physics_ms: 2, gpu_ms: 4, memory_mb: 200, nodes: 900 };

test("a metric worse beyond the tolerance and the floor is a regression", () => {
	const r = compare({ ...base, frame_ms_p95: 20 }, base, 0.15);
	assert.deepEqual(r.map((x) => x.metric), ["frame_ms_p95"]);
	assert.ok(Math.abs(r[0]!.change - 1 / 3) < 1e-9);
});

test("small or within-tolerance differences are not", () => {
	assert.deepEqual(compare({ ...base, frame_ms_mean: 11 }, base, 0.15), []);
	// 18% worse but only 0.25 ms, under the floor: noise.
	assert.deepEqual(compare({ ...base, physics_ms: 1.65 }, { ...base, physics_ms: 1.4 }, 0.15).length, 0);
	assert.deepEqual(compare({ ...base, frame_ms_mean: 5 }, base, 0.15), []);
});

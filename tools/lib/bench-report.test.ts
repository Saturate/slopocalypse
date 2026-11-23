import assert from "node:assert/strict";
import { test } from "node:test";
import type { Summary } from "./bench.ts";
import { renderReport, type BenchReport } from "./bench-report.ts";

const summary: Summary = {
	samples: 40, frame_ms_mean: 11, frame_ms_p95: 15, frame_ms_worst: 60, physics_ms: 1, physics_peak_ms: 4, gpu_ms: 7, render_cpu_ms: 2,
	draw_calls: 1200, objects_drawn: 900, primitives: 3_000_000, memory_mb: 900, nodes: 5000, driver: "vulkan",
	budget_scripts_ms: 4, budget_physics_ms: 1, budget_render_ms: 4, budget_other_ms: 2,
	visible_draw_calls: 500, visible_objects: 400, visible_primitives: 2000, shadow_draw_calls: 700, shadow_objects: 600, shadow_primitives: 4000,
};

const report: BenchReport = {
	date: "2026-11-19T10:00:00",
	machine: "darwin arm64, Apple M5 Pro, 18 threads",
	commit: "abc1234",
	results: [
		{
			name: "solo-city",
			what: "city walk",
			summary,
			baseline: { ...summary, frame_ms_mean: 10 },
			regressions: [],
			zones: [["world/voxels", 900.5], ["player/player_controller:physics", 120]],
			modules: [["world", 1000], ["player", 150]],
			spikes: [{ t: 30, ms: 80, zones: { "world/scenery_build": 50 }, compiles: { draw: 2 } }],
			server: { ticks_per_second: 60, scripts_ms_per_tick: 1.5, physics_ms_per_tick: 1, busy_ms_per_tick: 2.5, tick_share: 0.15 },
		},
	],
	failures: [{ name: "server-crowd", error: "server-crowd timed out" }],
	ablation: {
		scenario: "solo-city",
		full: summary,
		deltas: [{ name: "shadows off", frame_ms: -3, share: -0.27, scripts_ms: 0, physics_ms: 0, render_ms: -2.5, other_ms: -0.5, gpu_ms: -3, draw_calls: -700 }],
		failures: [{ name: "city off", error: "no samples" }],
	},
};

test("the report has the budget table, the details per scenario, the ablation and what failed", () => {
	const md = renderReport(report);
	assert.match(md, /^# Bench report 2026-11-19T10:00:00/);
	assert.match(md, /\| solo-city \| 11 \| 15 \| 4 \| 1 \| 4 \| 2 \| 7 \(vulkan\) \| 40 \|/);
	assert.match(md, /world\/voxels \| 900\.5/);
	assert.match(md, /\| world \| 1000 \|/);
	assert.match(md, /80 ms at 30 s: world\/scenery_build 50; compiled 2 draw/);
	assert.match(md, /shadow passes 700 draws/);
	assert.match(md, /Server \(solo\): 60 ticks\/s/);
	assert.match(md, /frame_ms_mean \| 11 \| 10 \| \+10\.0%/);
	assert.match(md, /\| shadows off \| -3 \| -27% \| 0 \| 0 \| -2\.5 \| -0\.5 \| -3 \| -700 \|/);
	assert.match(md, /city off: no samples/);
	assert.match(md, /server-crowd: server-crowd timed out/);
});

test("an untimed GPU and a missing baseline say so instead of printing zeros", () => {
	const md = renderReport({ ...report, results: [{ ...report.results[0]!, summary: { ...summary, gpu_ms: null, driver: "metal" }, baseline: undefined }], ablation: undefined, failures: [] });
	assert.match(md, /untimed \(metal\)/);
	assert.match(md, /No baseline yet/);
	assert.doesNotMatch(md, /## Ablation/);
	assert.doesNotMatch(md, /## Failed/);
});

test("pipes in zone names and errors do not break the tables", () => {
	const md = renderReport({ ...report, failures: [{ name: "x", error: "a | b\nc" }] });
	assert.match(md, /x: a \\\| b c/);
});

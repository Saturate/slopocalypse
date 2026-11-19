import assert from "node:assert/strict";
import { test } from "node:test";
import { errorLines, printable, summariseReport } from "./report.ts";

const report = {
	kind: "bug",
	description: "slideshow in the house",
	time: "2026-11-19T10:00:00",
	system: { version: "0.8.0", os: "Windows 10", cpu: "Ryzen 5", cpu_cores: 12, memory_mb: 16000, gpu: "RX 6600", gpu_driver: ["AMD", "31.0"], renderer: "forward_plus (vulkan)", window: [1920, 1080] },
	settings: { fov_offset: 10, ui_scale: 1 },
	game: { mode: "solo", position: [12.5, 3, -40], uptime_seconds: 300 },
	perf: { fps: 41, frame_ms_mean: 24.1, frame_ms_p95: 30.2, draw_calls: 9000 },
};

test("the summary names the machine, the place and the frame rate", () => {
	const lines = summariseReport(report).join("\n");
	assert.match(lines, /bug: slideshow in the house/);
	assert.match(lines, /RX 6600/);
	assert.match(lines, /forward_plus \(vulkan\)/);
	assert.match(lines, /12\.5, 3, -40/);
	assert.match(lines, /41 fps/);
	assert.match(lines, /fov_offset 10/);
});

test("a report missing fields still summarises", () => {
	const lines = summariseReport({ kind: "bug" });
	assert.ok(lines.length > 0);
	assert.match(lines.join("\n"), /no description/);
});

test("error lines are picked out of a log, newest last", () => {
	const log = ["[INFO] ok", "ERROR: first", "  at: x", "SCRIPT ERROR: second", "[WARN] w", "ERROR: third"].join("\n");
	assert.deepEqual(errorLines(log, 2), ["SCRIPT ERROR: second", "ERROR: third"]);
});

test("escape codes from a report are not printed", () => {
	assert.equal(printable("red\u001b[31m text\u0007"), "red[31m text");
});

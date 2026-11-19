import assert from "node:assert/strict";
import { test } from "node:test";
import { ablationDeltas, budgetLine, parseBaseline, compare, moduleCosts, netCosts, parseBenchArgs, parsePerfLog, passesLine, renderingDriver, serverCost, summarise, worstSpikes, zoneCosts, type Summary } from "./bench.ts";

const log = [
	'{"t":1,"frames":60,"frame_ms_mean":30,"frame_ms_p95":50,"frame_ms_max":90,"physics_nodes_ms":2,"physics_peak_ms":9,"memory_mb":100,"nodes":500}',
	'{"t":11,"spike_ms":70,"nodes":900}',
	'{"t":12,"frames":60,"frame_ms_mean":10,"frame_ms_p95":14,"frame_ms_max":20,"physics_nodes_ms":1,"physics_peak_ms":5,"gpu_ms":3,"render_cpu_ms":1,"draw_calls":1000,"objects_drawn":500,"primitives":2000000,"memory_mb":200,"nodes":900}',
	'{"t":13,"frames":60,"frame_ms_mean":12,"frame_ms_p95":16,"frame_ms_max":40,"physics_nodes_ms":3,"physics_peak_ms":7,"gpu_ms":5,"render_cpu_ms":2,"draw_calls":1200,"objects_drawn":700,"primitives":3000000,"memory_mb":210,"nodes":950}',
	'{"t":14,"frames":6',
].join("\n");

test("samples after the warm-up summarise; spikes and cut-off lines are skipped", () => {
	const s = summarise(parsePerfLog(log), 10);
	assert.deepEqual(s, { ...EMPTY_PARTS, samples: 2, frame_ms_mean: 11, frame_ms_p95: 15, frame_ms_worst: 40, physics_ms: 2, physics_peak_ms: 6, gpu_ms: 4, render_cpu_ms: 1.5, draw_calls: 1100, objects_drawn: 600, primitives: 2_500_000, memory_mb: 210, nodes: 950 });
});

test("a headless server's log has no render numbers: no GPU time and zero draws", () => {
	const s = summarise(parsePerfLog('{"t":11,"frames":60,"frame_ms_mean":2,"frame_ms_p95":3,"frame_ms_max":4}'), 10);
	assert.equal(s.gpu_ms, null);
	assert.equal(s.draw_calls, 0);
});

const EMPTY_PARTS = { driver: "", budget_scripts_ms: 0, budget_physics_ms: 0, budget_render_ms: 0, budget_other_ms: 0, visible_draw_calls: 0, visible_objects: 0, visible_primitives: 0, shadow_draw_calls: 0, shadow_objects: 0, shadow_primitives: 0 };

const base: Summary = { ...EMPTY_PARTS, samples: 50, frame_ms_mean: 10, frame_ms_p95: 15, frame_ms_worst: 40, physics_ms: 2, physics_peak_ms: 6, gpu_ms: 4, render_cpu_ms: 1, draw_calls: 1000, objects_drawn: 500, primitives: 2_000_000, memory_mb: 200, nodes: 900 };

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

test("zone costs are microseconds per frame after the warm-up, most expensive first", () => {
	const recs = parsePerfLog([
		'{"t":1,"frames":60,"zones":{"a:physics":{"ms":99}}}',
		'{"t":12,"frames":60,"zones":{"a:physics":{"ms":60},"b:frame":{"ms":2}}}',
		'{"t":13,"frames":60,"zones":{"a:physics":{"ms":120}}}',
	].join("\n"));
	const zones = zoneCosts(recs, 10);
	// 60 ms over 60 frames is 1000 us a frame, 120 over 60 is 2000: 1500 on average.
	assert.deepEqual(zones, [["a:physics", 1500], ["b:frame", 16.667]]);
});

test("network spend averages the server's net blocks after the warm-up, biggest source first", () => {
	const recs = parsePerfLog([
		'{"t":5,"frames":60,"net":{"out_per_peer":999,"sources":{"sync/player":999}}}',
		'{"t":11,"frames":60,"net":{"out_per_peer":1000,"sources":{"sync/player":600,"event/a":100,"other":300}}}',
		'{"t":12,"frames":60,"net":{"out_per_peer":2000,"sources":{"sync/player":1400,"other":100}}}',
	].join("\n"));
	assert.deepEqual(netCosts(recs, 10), { outPerPeer: 1500, sources: [["sync/player", 1000], ["other", 200], ["event/a", 50]] });
	assert.equal(netCosts(parsePerfLog('{"t":11,"frames":60}'), 10), undefined);
});

test("worst spikes after the warm-up come out slowest first, with zones and shader compiles", () => {
	const text = [
		'{"t":2,"spike_ms":300,"nodes":10,"zones":{}}',
		'{"t":11,"spike_ms":40,"nodes":10,"zones":{"a":1.5}}',
		'{"t":12,"frames":60}',
		'{"t":13,"spike_ms":90,"nodes":10,"zones":{"b":0.2},"compiles":{"draw":3}}',
		'{"t":14,"spike_ms":60,"nodes":10}',
	].join("\n");
	const out = worstSpikes(text, 10, 2);
	assert.deepEqual(out, [
		{ t: 13, ms: 90, zones: { b: 0.2 }, compiles: { draw: 3 } },
		{ t: 14, ms: 60, zones: {}, compiles: {} },
	]);
});

const budgetLog = [
	'{"t":11,"frames":100,"frame_ms_mean":10,"driver":"vulkan","gpu_ms":6,"budget":{"frame_ms":10,"scripts_ms":3,"physics_ms":1,"render_ms":4,"other_ms":2},"visible":{"draw_calls":400,"objects":300,"primitives":1000},"shadow":{"draw_calls":600,"objects":500,"primitives":3000},"modules":{"world":2,"player":0.5}}',
	'{"t":12,"frames":100,"frame_ms_mean":12,"driver":"vulkan","gpu_ms":8,"budget":{"frame_ms":12,"scripts_ms":5,"physics_ms":1,"render_ms":4,"other_ms":2},"visible":{"draw_calls":600,"objects":500,"primitives":3000},"shadow":{"draw_calls":800,"objects":700,"primitives":5000},"modules":{"world":4,"enemies":1}}',
].join("\n");

test("the frame budget, both passes and the driver summarise from the samples", () => {
	const s = summarise(parsePerfLog(budgetLog), 10);
	assert.equal(s.budget_scripts_ms, 4);
	assert.equal(s.budget_physics_ms, 1);
	assert.equal(s.budget_render_ms, 4);
	assert.equal(s.budget_other_ms, 2);
	assert.equal(s.gpu_ms, 7);
	assert.equal(s.driver, "vulkan");
	assert.equal(s.visible_draw_calls, 500);
	assert.equal(s.shadow_objects, 600);
	assert.equal(s.shadow_primitives, 4000);
});

test("a driver that cannot time the GPU (no gpu_ms in its samples) summarises as untimed", () => {
	const s = summarise(parsePerfLog('{"t":11,"frames":60,"frame_ms_mean":8,"driver":"metal","draw_calls":10}'), 10);
	assert.equal(s.gpu_ms, null);
	assert.match(budgetLine(s), /GPU untimed by metal/);
});

test("the budget line stacks the parts and names the driver that timed the GPU", () => {
	const s = summarise(parsePerfLog(budgetLog), 10);
	assert.equal(budgetLine(s), "frame 11 ms = scripts 4 + physics 1 + render 4 + other 2; GPU 7 ms (vulkan)");
	assert.equal(passesLine(s), "visible pass 500 draws, 400 objects, 2000 primitives; shadow passes 700 draws, 600 objects, 4000 primitives");
});

test("modules are averaged microseconds per frame, biggest first", () => {
	// A module missing from a sample spent nothing in it.
	assert.deepEqual(moduleCosts(parsePerfLog(budgetLog), 10), [["world", 3000], ["enemies", 500], ["player", 250]]);
});

test("a baseline that predates a metric, or a GPU nobody timed, is no regression", () => {
	const { budget_scripts_ms: _dropped, ...old } = base;
	assert.deepEqual(compare({ ...base, budget_scripts_ms: 9, gpu_ms: null }, old, 0.15), []);
});

test("the server's tick cost is its scripts and physics per physics tick", () => {
	const recs = parsePerfLog([
		'{"t":5,"frames":100,"physics_ticks":60,"budget":{"scripts_ms":99,"physics_ms":99}}',
		// 100 frames: 1.2 ms of scripts and 0.6 of physics a frame = 120 and 60 ms over 60 ticks.
		'{"t":11,"frames":100,"frame_ms_mean":10,"physics_ticks":60,"physics_nodes_ms":0.5,"budget":{"scripts_ms":1.2,"physics_ms":0.6}}',
		'{"t":12,"frames":100,"frame_ms_mean":10,"physics_ticks":60,"physics_nodes_ms":0.7,"budget":{"scripts_ms":0.6,"physics_ms":0.6}}',
	].join("\n"));
	assert.deepEqual(serverCost(recs, 10), { ticks_per_second: 60, scripts_ms_per_tick: 1.5, physics_ms_per_tick: 1, busy_ms_per_tick: 2.5, tick_share: 0.15 });
	assert.equal(serverCost(parsePerfLog('{"t":11,"frames":60}'), 10), undefined);
});

test("a server that cannot keep up runs fewer ticks a second of wall time than 60", () => {
	// Godot slows the game clock when the ticks fall behind: a "second" of samples took 2.4 s.
	const recs = parsePerfLog('{"t":11,"frames":8,"frame_ms_mean":300,"physics_ticks":64,"budget":{"scripts_ms":280,"physics_ms":10}}');
	const c = serverCost(recs, 10);
	assert.equal(c?.ticks_per_second, 26.7);
	assert.equal(c?.busy_ms_per_tick, 36.25);
});

test("ablation deltas are each variant against the full run, cheapest-to-drop first", () => {
	const full: Summary = { ...base, frame_ms_mean: 10, budget_render_ms: 5, gpu_ms: 8, draw_calls: 1000 };
	const rows = ablationDeltas(full, [
		["shadows off", { ...full, frame_ms_mean: 7, budget_render_ms: 2.5, gpu_ms: 5, draw_calls: 400 }],
		["characters off", { ...full, frame_ms_mean: 9, gpu_ms: null }],
	]);
	assert.deepEqual(rows, [
		{ name: "shadows off", frame_ms: -3, share: -0.3, scripts_ms: 0, physics_ms: 0, render_ms: -2.5, other_ms: 0, gpu_ms: -3, draw_calls: -600 },
		{ name: "characters off", frame_ms: -1, share: -0.1, scripts_ms: 0, physics_ms: 0, render_ms: 0, other_ms: 0, gpu_ms: null, draw_calls: 0 },
	]);
});

test("bench arguments: scenarios, all, ablate and options with values", () => {
	const a = parseBenchArgs(["solo-city", "--ablate", "--tolerance", "0.2", "--driver", "metal"], ["solo-walk", "solo-city"]);
	assert.deepEqual(a, { scenarios: ["solo-city"], ablate: true, all: false, saveBaseline: false, tolerance: 0.2, driver: "metal", serverFlags: undefined, crowd: 30 });
	const all = parseBenchArgs(["all"], ["solo-walk", "solo-city"]);
	assert.deepEqual([all.scenarios, all.ablate, all.all], [["solo-walk", "solo-city"], true, true]);
	assert.deepEqual(parseBenchArgs([], ["a", "b"]).scenarios, ["a", "b"]);
	assert.throws(() => parseBenchArgs(["nope"], ["a"]), /unknown scenario nope/);
	assert.throws(() => parseBenchArgs(["--tolerance"], ["a"]), /--tolerance needs a value/);
});

test("macOS benches with Vulkan unless told otherwise: Metal cannot time the GPU", () => {
	assert.equal(renderingDriver("darwin", undefined), "vulkan");
	assert.equal(renderingDriver("darwin", "metal"), "metal");
	assert.equal(renderingDriver("win32", undefined), undefined);
	assert.equal(renderingDriver("linux", "opengl3"), "opengl3");
});

test("a saved baseline keeps its numeric metrics; anything else in the file is dropped", () => {
	assert.deepEqual(parseBaseline('{"samples":5,"frame_ms_mean":10,"gpu_ms":null,"nodes":"many","junk":1}'), { frame_ms_mean: 10 });
	assert.equal(parseBaseline("not json"), undefined);
	assert.equal(parseBaseline("[1,2]"), undefined);
});

import assert from "node:assert/strict";
import { test } from "node:test";
import { compare, netCosts, parsePerfLog, summarise, worstSpikes, zoneCosts, type Summary } from "./bench.ts";

const log = [
	'{"t":1,"frames":60,"frame_ms_mean":30,"frame_ms_p95":50,"frame_ms_max":90,"physics_nodes_ms":2,"physics_peak_ms":9,"memory_mb":100,"nodes":500}',
	'{"t":11,"spike_ms":70,"nodes":900}',
	'{"t":12,"frames":60,"frame_ms_mean":10,"frame_ms_p95":14,"frame_ms_max":20,"physics_nodes_ms":1,"physics_peak_ms":5,"gpu_ms":3,"render_cpu_ms":1,"draw_calls":1000,"objects_drawn":500,"primitives":2000000,"memory_mb":200,"nodes":900}',
	'{"t":13,"frames":60,"frame_ms_mean":12,"frame_ms_p95":16,"frame_ms_max":40,"physics_nodes_ms":3,"physics_peak_ms":7,"gpu_ms":5,"render_cpu_ms":2,"draw_calls":1200,"objects_drawn":700,"primitives":3000000,"memory_mb":210,"nodes":950}',
	'{"t":14,"frames":6',
].join("\n");

test("samples after the warm-up summarise; spikes and cut-off lines are skipped", () => {
	const s = summarise(parsePerfLog(log), 10);
	assert.deepEqual(s, { samples: 2, frame_ms_mean: 11, frame_ms_p95: 15, frame_ms_worst: 40, physics_ms: 2, physics_peak_ms: 6, gpu_ms: 4, render_cpu_ms: 1.5, draw_calls: 1100, objects_drawn: 600, primitives: 2_500_000, memory_mb: 210, nodes: 950 });
});

test("a headless server's log has no render numbers: they summarise as zero", () => {
	const s = summarise(parsePerfLog('{"t":11,"frames":60,"frame_ms_mean":2,"frame_ms_p95":3,"frame_ms_max":4}'), 10);
	assert.equal(s.gpu_ms, 0);
	assert.equal(s.draw_calls, 0);
});

const base: Summary = { samples: 50, frame_ms_mean: 10, frame_ms_p95: 15, frame_ms_worst: 40, physics_ms: 2, physics_peak_ms: 6, gpu_ms: 4, render_cpu_ms: 1, draw_calls: 1000, objects_drawn: 500, primitives: 2_000_000, memory_mb: 200, nodes: 900 };

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

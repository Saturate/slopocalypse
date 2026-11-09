// Pure parts of tools/bench.ts: reading a perf log, summarising it and comparing with a
// baseline. Lower is better for every metric.

export interface Summary {
	samples: number;
	frame_ms_mean: number;
	frame_ms_p95: number;
	frame_ms_worst: number;
	physics_ms: number;
	physics_peak_ms: number;
	gpu_ms: number;
	memory_mb: number;
	nodes: number;
}

export const METRICS: readonly (keyof Omit<Summary, "samples">)[] = ["frame_ms_mean", "frame_ms_p95", "frame_ms_worst", "physics_ms", "physics_peak_ms", "gpu_ms", "memory_mb", "nodes"];

// Differences smaller than this are noise however large in percent (a 0.1 ms frame doubling).
export const FLOOR: Readonly<Record<(typeof METRICS)[number], number>> = {
	frame_ms_mean: 0.5,
	frame_ms_p95: 1.0,
	frame_ms_worst: 5.0,
	physics_ms: 0.3,
	physics_peak_ms: 5.0,
	gpu_ms: 0.5,
	memory_mb: 20,
	nodes: 200,
};

function num(rec: Record<string, unknown>, key: string): number {
	const v = rec[key];
	return typeof v === "number" ? v : 0;
}

// Sample lines of a perf log (spike lines and junk skipped).
export function parsePerfLog(text: string): Record<string, unknown>[] {
	const out: Record<string, unknown>[] = [];
	for (const line of text.split(/\r?\n/)) {
		if (line.trim() === "") continue;
		try {
			const rec: unknown = JSON.parse(line);
			if (typeof rec === "object" && rec !== null && !Array.isArray(rec) && "frames" in rec) out.push(rec as Record<string, unknown>);
		} catch {
			// A line cut short when the process was killed.
		}
	}
	return out;
}

const round = (n: number, places = 2): number => Math.round(n * 10 ** places) / 10 ** places;

export function summarise(records: readonly Record<string, unknown>[], warmupSeconds: number): Summary {
	const used = records.filter((r) => num(r, "t") >= warmupSeconds && num(r, "frames") > 0);
	const mean = (key: string): number => (used.length === 0 ? 0 : used.reduce((s, r) => s + num(r, key), 0) / used.length);
	const max = (key: string): number => used.reduce((m, r) => Math.max(m, num(r, key)), 0);
	return {
		samples: used.length,
		frame_ms_mean: round(mean("frame_ms_mean")),
		frame_ms_p95: round(mean("frame_ms_p95")),
		frame_ms_worst: round(max("frame_ms_max")),
		// Nodes' physics per tick, measured by the perf module's probe.
		physics_ms: round(mean("physics_nodes_ms")),
		physics_peak_ms: round(mean("physics_peak_ms")),
		gpu_ms: round(mean("gpu_ms")),
		memory_mb: round(max("memory_mb"), 1),
		nodes: max("nodes"),
	};
}

export interface Regression {
	metric: string;
	baseline: number;
	now: number;
	change: number;
}

// Mean microseconds per frame for each profile zone after the warm-up, most expensive first.
// Per frame, not per second: an uncapped client runs hundreds of frames a second, which would
// inflate a per-second figure for the same work.
export function zoneCosts(records: readonly Record<string, unknown>[], warmupSeconds: number): [string, number][] {
	const used = records.filter((r) => num(r, "t") >= warmupSeconds && num(r, "frames") > 0);
	const totals = new Map<string, number>();
	for (const r of used) {
		const zones = r["zones"];
		if (typeof zones !== "object" || zones === null) continue;
		for (const [name, z] of Object.entries(zones)) {
			const ms = typeof z === "object" && z !== null ? Reflect.get(z, "ms") : undefined;
			if (typeof ms === "number") totals.set(name, (totals.get(name) ?? 0) + (ms * 1000) / num(r, "frames"));
		}
	}
	return [...totals].map(([name, ms]): [string, number] => [name, round(ms / Math.max(used.length, 1), 3)]).sort((a, b) => b[1] - a[1]);
}

export function compare(now: Summary, baseline: Summary, tolerance: number): Regression[] {
	const out: Regression[] = [];
	for (const m of METRICS) {
		const b = baseline[m];
		const n = now[m];
		if (n - b > FLOOR[m] && n > b * (1 + tolerance)) out.push({ metric: m, baseline: b, now: n, change: b === 0 ? Infinity : (n - b) / b });
	}
	return out;
}

export function table(rows: readonly [string, Summary, Summary | undefined][]): string {
	const lines: string[] = [];
	for (const [name, s, base] of rows) {
		lines.push(`${name} (${s.samples} samples)`);
		for (const m of METRICS) {
			const delta = base === undefined ? "" : `  (baseline ${base[m]}, ${base[m] === 0 ? "n/a" : `${((s[m] - base[m]) / base[m] * 100).toFixed(1)}%`})`;
			lines.push(`  ${m.padEnd(15)} ${String(s[m]).padStart(10)}${delta}`);
		}
	}
	return lines.join("\n");
}

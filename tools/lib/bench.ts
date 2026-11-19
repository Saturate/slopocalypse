// Pure parts of tools/bench.ts: reading a perf log, summarising it, comparing with a
// baseline, the frame budget, the server's tick cost, ablation deltas and the arguments.
// Lower is better for every metric.

export interface Summary {
	samples: number;
	frame_ms_mean: number;
	frame_ms_p95: number;
	frame_ms_worst: number;
	physics_ms: number;
	physics_peak_ms: number;
	// What drawing a frame costs the graphics card and the processor's render thread, and
	// how much it draws: zero on a headless server. `gpu_ms` is null when nothing timed the GPU
	// (a headless server, or a driver without GPU timers such as Metal).
	gpu_ms: number | null;
	render_cpu_ms: number;
	draw_calls: number;
	objects_drawn: number;
	primitives: number;
	memory_mb: number;
	nodes: number;
	// The rendering driver the client ran ("" headless): says what timed the GPU.
	driver: string;
	// The mean frame split on the main thread (modules/perf PerfBudget): every moment a profile
	// zone ran, the physics step outside zones, RenderingServer drawing (waiting on the GPU
	// included), and the rest. They add up to frame_ms_mean.
	budget_scripts_ms: number;
	budget_physics_ms: number;
	budget_render_ms: number;
	budget_other_ms: number;
	// What the camera's pass drew against what the shadow maps drew.
	visible_draw_calls: number;
	visible_objects: number;
	visible_primitives: number;
	shadow_draw_calls: number;
	shadow_objects: number;
	shadow_primitives: number;
}

type Metric = Exclude<keyof Summary, "samples" | "driver">;

export const METRICS: readonly Metric[] = ["frame_ms_mean", "frame_ms_p95", "frame_ms_worst", "budget_scripts_ms", "budget_physics_ms", "budget_render_ms", "budget_other_ms", "physics_ms", "physics_peak_ms", "gpu_ms", "render_cpu_ms", "draw_calls", "objects_drawn", "primitives", "visible_draw_calls", "visible_objects", "visible_primitives", "shadow_draw_calls", "shadow_objects", "shadow_primitives", "memory_mb", "nodes"];

// Differences smaller than this are noise however large in percent (a 0.1 ms frame doubling).
export const FLOOR: Readonly<Record<Metric, number>> = {
	frame_ms_mean: 0.5,
	frame_ms_p95: 1.0,
	frame_ms_worst: 5.0,
	budget_scripts_ms: 0.5,
	budget_physics_ms: 0.3,
	budget_render_ms: 0.5,
	budget_other_ms: 0.5,
	visible_draw_calls: 100,
	visible_objects: 100,
	visible_primitives: 100_000,
	shadow_draw_calls: 100,
	shadow_objects: 100,
	shadow_primitives: 100_000,
	physics_ms: 0.3,
	physics_peak_ms: 5.0,
	gpu_ms: 0.5,
	render_cpu_ms: 0.5,
	draw_calls: 100,
	objects_drawn: 100,
	primitives: 100_000,
	memory_mb: 20,
	nodes: 200,
};

function num(rec: Record<string, unknown>, key: string): number {
	const v = rec[key];
	return typeof v === "number" ? v : 0;
}

// `rec[group][key]` as a number, 0 when either is missing.
function nested(rec: Record<string, unknown>, group: string, key: string): number {
	const g = rec[group];
	if (typeof g !== "object" || g === null) return 0;
	const v: unknown = Reflect.get(g, key);
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

export interface Spike {
	t: number;
	ms: number;
	// Script zones that ran in the slow frame (ms each) and shader pipelines compiled in it.
	zones: Record<string, number>;
	compiles: Record<string, number>;
}

function numbers(v: unknown): Record<string, number> {
	const out: Record<string, number> = {};
	if (typeof v !== "object" || v === null || Array.isArray(v)) return out;
	for (const [k, n] of Object.entries(v)) if (typeof n === "number") out[k] = n;
	return out;
}

// The `n` slowest spike lines after the warm-up, slowest first: the hitches a player feels,
// and what ran in each.
export function worstSpikes(text: string, warmupSeconds: number, n: number): Spike[] {
	const out: Spike[] = [];
	for (const line of text.split(/\r?\n/)) {
		let rec: unknown;
		try {
			rec = JSON.parse(line);
		} catch {
			continue;
		}
		if (typeof rec !== "object" || rec === null || !("spike_ms" in rec) || !("t" in rec)) continue;
		const { t, spike_ms: ms } = rec;
		if (typeof t !== "number" || typeof ms !== "number" || t < warmupSeconds) continue;
		out.push({ t, ms, zones: numbers("zones" in rec ? rec.zones : undefined), compiles: numbers("compiles" in rec ? rec.compiles : undefined) });
	}
	return out.sort((a, b) => b.ms - a.ms).slice(0, n);
}

const round = (n: number, places = 2): number => Math.round(n * 10 ** places) / 10 ** places;

export function summarise(records: readonly Record<string, unknown>[], warmupSeconds: number): Summary {
	const used = records.filter((r) => num(r, "t") >= warmupSeconds && num(r, "frames") > 0);
	const mean = (key: string): number => (used.length === 0 ? 0 : used.reduce((s, r) => s + num(r, key), 0) / used.length);
	const meanOf = (group: string, key: string): number => (used.length === 0 ? 0 : used.reduce((s, r) => s + nested(r, group, key), 0) / used.length);
	const max = (key: string): number => used.reduce((m, r) => Math.max(m, num(r, key)), 0);
	// Only samples that timed the GPU: a driver that cannot leaves gpu_ms out.
	const timed = used.filter((r) => typeof r["gpu_ms"] === "number");
	const last = used.at(-1)?.["driver"];
	return {
		samples: used.length,
		frame_ms_mean: round(mean("frame_ms_mean")),
		frame_ms_p95: round(mean("frame_ms_p95")),
		frame_ms_worst: round(max("frame_ms_max")),
		// Nodes' physics per tick, measured by the perf module's probe.
		physics_ms: round(mean("physics_nodes_ms")),
		physics_peak_ms: round(mean("physics_peak_ms")),
		gpu_ms: timed.length === 0 ? null : round(timed.reduce((s, r) => s + num(r, "gpu_ms"), 0) / timed.length),
		render_cpu_ms: round(mean("render_cpu_ms")),
		draw_calls: Math.round(mean("draw_calls")),
		objects_drawn: Math.round(mean("objects_drawn")),
		primitives: Math.round(mean("primitives")),
		memory_mb: round(max("memory_mb"), 1),
		nodes: max("nodes"),
		driver: typeof last === "string" ? last : "",
		budget_scripts_ms: round(meanOf("budget", "scripts_ms")),
		budget_physics_ms: round(meanOf("budget", "physics_ms")),
		budget_render_ms: round(meanOf("budget", "render_ms")),
		budget_other_ms: round(meanOf("budget", "other_ms")),
		visible_draw_calls: Math.round(meanOf("visible", "draw_calls")),
		visible_objects: Math.round(meanOf("visible", "objects")),
		visible_primitives: Math.round(meanOf("visible", "primitives")),
		shadow_draw_calls: Math.round(meanOf("shadow", "draw_calls")),
		shadow_objects: Math.round(meanOf("shadow", "objects")),
		shadow_primitives: Math.round(meanOf("shadow", "primitives")),
	};
}

// "frame 11 ms = scripts 4 + physics 1 + render 4 + other 2; GPU 7 ms (vulkan)".
export function budgetLine(s: Summary): string {
	const gpu = s.gpu_ms === null ? (s.driver === "" ? "no GPU (headless)" : `GPU untimed by ${s.driver}`) : `GPU ${s.gpu_ms} ms (${s.driver || "?"})`;
	return `frame ${s.frame_ms_mean} ms = scripts ${s.budget_scripts_ms} + physics ${s.budget_physics_ms} + render ${s.budget_render_ms} + other ${s.budget_other_ms}; ${gpu}`;
}

export function passesLine(s: Summary): string {
	return `visible pass ${s.visible_draw_calls} draws, ${s.visible_objects} objects, ${s.visible_primitives} primitives; shadow passes ${s.shadow_draw_calls} draws, ${s.shadow_objects} objects, ${s.shadow_primitives} primitives`;
}

// Mean microseconds per frame for each module (the perf module's `modules`: zones summed by
// module, nested zones of one module counted twice), most expensive first.
export function moduleCosts(records: readonly Record<string, unknown>[], warmupSeconds: number): [string, number][] {
	const used = records.filter((r) => num(r, "t") >= warmupSeconds && num(r, "frames") > 0);
	const totals = new Map<string, number>();
	for (const r of used) for (const [name, ms] of Object.entries(numbers(r["modules"]))) totals.set(name, (totals.get(name) ?? 0) + ms * 1000);
	return [...totals].map(([name, us]): [string, number] => [name, round(us / Math.max(used.length, 1), 1)]).sort((a, b) => b[1] - a[1]);
}

export interface ServerCost {
	// Physics ticks a second of wall time: under 60 means the server is falling behind.
	ticks_per_second: number;
	// Mean milliseconds of work per physics tick: zones, and the physics step outside them.
	scripts_ms_per_tick: number;
	physics_ms_per_tick: number;
	busy_ms_per_tick: number;
	// busy_ms_per_tick over the 1/60 s a tick has.
	tick_share: number;
}

const TICK_MS = 1000 / 60;

// A server's work per physics tick after the warm-up: its frame times mean nothing (a headless
// process sleeps between frames), what it does per tick does. Undefined without budgets.
export function serverCost(records: readonly Record<string, unknown>[], warmupSeconds: number): ServerCost | undefined {
	const used = records.filter((r) => num(r, "t") >= warmupSeconds && num(r, "physics_ticks") > 0 && typeof r["budget"] === "object");
	if (used.length === 0) return undefined;
	const perTick = (key: string): number => used.reduce((s, r) => s + (nested(r, "budget", key) * num(r, "frames")) / num(r, "physics_ticks"), 0) / used.length;
	const scripts = perTick("scripts_ms");
	const physics = perTick("physics_ms");
	return {
		// By the wall clock: when ticks fall behind, Godot slows the game clock the samples keep.
		ticks_per_second: round((used.reduce((s, r) => s + num(r, "physics_ticks"), 0) * 1000) / Math.max(used.reduce((s, r) => s + num(r, "frames") * num(r, "frame_ms_mean"), 0), 1), 1),
		scripts_ms_per_tick: round(scripts),
		physics_ms_per_tick: round(physics),
		busy_ms_per_tick: round(scripts + physics),
		tick_share: round((scripts + physics) / TICK_MS),
	};
}

export function serverLine(c: ServerCost): string {
	return `${c.ticks_per_second} ticks/s; per tick: scripts ${c.scripts_ms_per_tick} ms + physics ${c.physics_ms_per_tick} ms = ${c.busy_ms_per_tick} ms, ${(c.tick_share * 100).toFixed(0)}% of a 60 Hz tick`;
}

export interface AblationDelta {
	name: string;
	// Each is the variant minus the full run: negative is what switching the thing off saves.
	frame_ms: number;
	// frame_ms over the full run's frame.
	share: number;
	scripts_ms: number;
	physics_ms: number;
	render_ms: number;
	other_ms: number;
	gpu_ms: number | null;
	draw_calls: number;
}

// What each thing costs: every variant (one thing off) against the full run, the biggest
// saving first.
export function ablationDeltas(full: Summary, variants: readonly [string, Summary][]): AblationDelta[] {
	return variants
		.map(([name, v]): AblationDelta => ({
			name,
			frame_ms: round(v.frame_ms_mean - full.frame_ms_mean),
			share: full.frame_ms_mean === 0 ? 0 : round((v.frame_ms_mean - full.frame_ms_mean) / full.frame_ms_mean, 3),
			scripts_ms: round(v.budget_scripts_ms - full.budget_scripts_ms),
			physics_ms: round(v.budget_physics_ms - full.budget_physics_ms),
			render_ms: round(v.budget_render_ms - full.budget_render_ms),
			other_ms: round(v.budget_other_ms - full.budget_other_ms),
			gpu_ms: v.gpu_ms === null || full.gpu_ms === null ? null : round(v.gpu_ms - full.gpu_ms),
			draw_calls: v.draw_calls - full.draw_calls,
		}))
		.sort((a, b) => a.frame_ms - b.frame_ms);
}

export interface BenchArgs {
	scenarios: string[];
	// Rerun solo-city once per switch in ABLATIONS.
	ablate: boolean;
	// `all`: every scenario, the ablation, and a Markdown report.
	all: boolean;
	saveBaseline: boolean;
	tolerance: number;
	driver: string | undefined;
	serverFlags: string | undefined;
	crowd: number;
}

const VALUED = ["tolerance", "driver", "server-flags", "crowd"];

export function parseBenchArgs(args: readonly string[], known: readonly string[]): BenchArgs {
	const values = new Map<string, string>();
	const names: string[] = [];
	const switches = new Set<string>();
	for (let i = 0; i < args.length; i++) {
		const a = args[i]!;
		if (!a.startsWith("--")) {
			names.push(a);
			continue;
		}
		const key = a.slice(2);
		if (!VALUED.includes(key)) {
			switches.add(key);
			continue;
		}
		const v = args[i + 1];
		if (v === undefined || v.startsWith("--")) throw new Error(`${a} needs a value`);
		values.set(key, v);
		i++;
	}
	const all = names.includes("all");
	const asked = names.filter((n) => n !== "all");
	for (const n of asked) if (!known.includes(n)) throw new Error(`unknown scenario ${n}; known: all, ${known.join(", ")}`);
	return {
		scenarios: all || asked.length === 0 ? [...known] : asked,
		ablate: all || switches.has("ablate"),
		all,
		saveBaseline: switches.has("save-baseline"),
		tolerance: Number(values.get("tolerance") ?? "0.15"),
		driver: values.get("driver"),
		serverFlags: values.get("server-flags"),
		crowd: Number(values.get("crowd") ?? "30"),
	};
}

// The rendering driver a windowed bench asks for: the one given, else Vulkan on macOS, where
// Godot 4.7's Metal driver has no GPU timers (its timestamp queries are stubs returning zero)
// and the pinned build carries MoltenVK. Undefined: the engine's default.
export function renderingDriver(os: string, asked: string | undefined): string | undefined {
	if (asked !== undefined) return asked;
	return os === "darwin" ? "vulkan" : undefined;
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

export interface NetCost {
	// Mean bytes a second the server sent each peer (ENet's exact total over the peers).
	outPerPeer: number;
	// Mean estimated bytes a second by source (see NetStats), most first; "other" is what the
	// estimates leave unexplained.
	sources: [string, number][];
}

// The server's network spend after the warm-up, from the perf module's `net` blocks; undefined
// when the log has none (a client, or nobody connected).
export function netCosts(records: readonly Record<string, unknown>[], warmupSeconds: number): NetCost | undefined {
	const used = records.filter((r) => num(r, "t") >= warmupSeconds && typeof r["net"] === "object" && r["net"] !== null);
	if (used.length === 0) return undefined;
	let out = 0;
	const totals = new Map<string, number>();
	for (const r of used) {
		const net = r["net"];
		if (typeof net !== "object" || net === null) continue;
		const per = Reflect.get(net, "out_per_peer");
		if (typeof per === "number") out += per;
		const sources = Reflect.get(net, "sources");
		if (typeof sources !== "object" || sources === null) continue;
		for (const [name, bytes] of Object.entries(sources)) {
			if (typeof bytes === "number") totals.set(name, (totals.get(name) ?? 0) + bytes);
		}
	}
	return {
		outPerPeer: Math.round(out / used.length),
		sources: [...totals].map(([name, b]): [string, number] => [name, Math.round(b / used.length)]).sort((a, b) => b[1] - a[1]),
	};
}

// A baseline file's metrics: only the numbers it holds under a known metric's name. Undefined
// when it is not a JSON object (a file cut short, edited by hand).
export function parseBaseline(text: string): Partial<Summary> | undefined {
	let data: unknown;
	try {
		data = JSON.parse(text);
	} catch {
		return undefined;
	}
	if (typeof data !== "object" || data === null || Array.isArray(data)) return undefined;
	const out: Partial<Summary> = {};
	for (const m of METRICS) {
		const v: unknown = Reflect.get(data, m);
		if (typeof v === "number") out[m] = v;
	}
	return out;
}

// `baseline` is what an earlier run saved: it may predate a metric, so any can be missing.
export function compare(now: Summary, baseline: Partial<Summary>, tolerance: number): Regression[] {
	const out: Regression[] = [];
	for (const m of METRICS) {
		const b = baseline[m];
		const n = now[m];
		if (typeof b !== "number" || n === null) continue;
		if (n - b > FLOOR[m] && n > b * (1 + tolerance)) out.push({ metric: m, baseline: b, now: n, change: b === 0 ? Infinity : (n - b) / b });
	}
	return out;
}

export function table(rows: readonly [string, Summary, Partial<Summary> | undefined][]): string {
	const lines: string[] = [];
	for (const [name, s, base] of rows) {
		lines.push(`${name} (${s.samples} samples)`);
		for (const m of METRICS) {
			const now = s[m];
			const b = base?.[m];
			const delta = typeof b !== "number" ? "" : `  (baseline ${b}, ${b === 0 || now === null ? "n/a" : `${(((now - b) / b) * 100).toFixed(1)}%`})`;
			lines.push(`  ${m.padEnd(19)} ${String(now ?? "untimed").padStart(10)}${delta}`);
		}
	}
	return lines.join("\n");
}

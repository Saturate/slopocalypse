// Pure parts of tools/report.ts: reading a report.json from the game's "Report a bug" (or
// the benchmark) into a few lines a person can scan.

type Json = Record<string, unknown>;

function obj(v: unknown): Json {
	if (typeof v !== "object" || v === null || Array.isArray(v)) return {};
	const out: Json = {};
	for (const [k, x] of Object.entries(v)) out[k] = x;
	return out;
}

function text(v: unknown, fallback = "?"): string {
	if (typeof v === "string" && v !== "") return v;
	if (typeof v === "number" || typeof v === "boolean") return String(v);
	if (Array.isArray(v)) return v.map((x) => text(x, "")).join(", ");
	return fallback;
}

// Lines for the terminal: what was reported, on what machine, where, and how it ran.
export function summariseReport(raw: unknown): string[] {
	const r = obj(raw);
	const sys = obj(r["system"]);
	const game = obj(r["game"]);
	const perf = obj(r["perf"]);
	const settings = obj(r["settings"]);
	const description = text(r["description"], "");
	const lines = [
		`${text(r["kind"])}: ${description === "" ? "(no description)" : printable(description)}`,
		`  at ${text(r["time"])} UTC, build ${text(sys["version"])}`,
		`  machine: ${text(sys["os"])}; ${text(sys["cpu"])} (${text(sys["cpu_cores"])} threads), ${text(sys["memory_mb"])} MB`,
		`  graphics: ${text(sys["gpu"])}, driver ${text(sys["gpu_driver"])}; ${text(sys["renderer"])}; window ${text(sys["window"])}`,
		`  game: ${text(game["mode"])}, up ${text(game["uptime_seconds"])} s, at ${text(game["position"], "(no player)")}${game["dead"] === true ? ", dead" : ""}`,
		`  frame: ${text(perf["fps"])} fps, mean ${text(perf["frame_ms_mean"])} ms, p95 ${text(perf["frame_ms_p95"])} ms, ${text(perf["draw_calls"])} draw calls`,
		`  settings: ${Object.entries(settings).map(([k, v]) => `${k} ${text(v)}`).join(", ") || "?"}`,
	];
	const perfBudget = budget(perf);
	if (perfBudget !== undefined) lines.push(`  frame budget: ${perfBudget}`);
	const perfPasses = passes(perf);
	if (perfPasses !== undefined) lines.push(`  passes: ${perfPasses}`);
	const bench = obj(r["benchmark"]);
	const numbers = Object.entries(bench).filter(([k, v]) => k !== "hitches" && (typeof v !== "object" || v === null));
	if (numbers.length > 0) lines.push(`  benchmark: ${numbers.map(([k, v]) => `${k} ${text(v)}`).join(", ")}`);
	const benchBudget = budget(bench);
	if (benchBudget !== undefined) lines.push(`  benchmark budget: ${benchBudget}`);
	const benchPasses = passes(bench);
	if (benchPasses !== undefined) lines.push(`  benchmark passes: ${benchPasses}`);
	const hitches: unknown[] = Array.isArray(bench["hitches"]) ? bench["hitches"] : [];
	for (const h of hitches) {
		const hitch = obj(h);
		const zones = Object.entries(obj(hitch["zones"])).map(([z, ms]) => `${z} ${text(ms)}`).join(", ");
		const compiles = Object.keys(obj(hitch["compiles"])).length > 0 ? "; shaders compiled" : "";
		lines.push(`    hitch ${text(hitch["ms"])} ms at ${text(hitch["t"])} s: ${zones || "no zones"}${compiles}`);
	}
	return lines;
}

// The perf module's frame budget (scripts, physics, render, other; GPU beside it) as one line,
// or undefined when the record has none (a build from before it).
function budget(rec: Json): string | undefined {
	const b = obj(rec["budget"]);
	if (Object.keys(b).length === 0) return undefined;
	const driver = text(rec["driver"]);
	const gpu = typeof rec["gpu_ms"] === "number" ? `GPU ${rec["gpu_ms"]} ms (${driver})` : `GPU untimed by ${driver}`;
	return `${text(b["frame_ms"])} ms = scripts ${text(b["scripts_ms"])} + physics ${text(b["physics_ms"])} + render ${text(b["render_ms"])} + other ${text(b["other_ms"])}; ${gpu}`;
}

// What the camera's pass and the shadow passes drew.
function passes(rec: Json): string | undefined {
	const v = obj(rec["visible"]);
	const sh = obj(rec["shadow"]);
	if (Object.keys(v).length === 0 && Object.keys(sh).length === 0) return undefined;
	return `visible ${text(v["draw_calls"])} draws, ${text(v["objects"])} objects; shadow ${text(sh["draw_calls"])} draws, ${text(sh["objects"])} objects`;
}

// `s` without control characters (bar tab and newline): a report is the tester's file, and
// escape codes in it must not drive the terminal it is printed in.
export function printable(s: string): string {
	return s.replace(/[\u0000-\u0008\u000b-\u001f\u007f-\u009f]/g, "");
}

// The last `n` error lines of a Godot log: what broke, without the stack lines under each.
export function errorLines(log: string, n: number): string[] {
	return log
		.split(/\r?\n/)
		.filter((l) => /^(SCRIPT ERROR|ERROR|Error):/.test(l))
		.slice(-n);
}

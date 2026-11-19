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
	const bench = obj(r["benchmark"]);
	const numbers = Object.entries(bench).filter(([k]) => k !== "hitches");
	if (numbers.length > 0) lines.push(`  benchmark: ${numbers.map(([k, v]) => `${k} ${text(v)}`).join(", ")}`);
	const hitches: unknown[] = Array.isArray(bench["hitches"]) ? bench["hitches"] : [];
	for (const h of hitches) {
		const hitch = obj(h);
		const zones = Object.entries(obj(hitch["zones"])).map(([z, ms]) => `${z} ${text(ms)}`).join(", ");
		const compiles = Object.keys(obj(hitch["compiles"])).length > 0 ? "; shaders compiled" : "";
		lines.push(`    hitch ${text(hitch["ms"])} ms at ${text(hitch["t"])} s: ${zones || "no zones"}${compiles}`);
	}
	return lines;
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

// Benchmarks: runs fixed scenarios, reads the perf logs each writes (the client's and, for a
// windowed solo game, its server's), and compares with this machine's baseline. Not part of
// the gate (timings are too noisy on shared machines).
//   node tools/bench.ts [all] [solo-walk] [solo-drive] [solo-city] [solo-deaths] [benchmark] [range-destroy] [server-bots] [server-crowd]
//     [--save-baseline] [--tolerance 0.15]
//     [--ablate]  (solo-city again with one thing off at a time: what each costs)
//     [--server-flags car:off,enemies:off]  (server-bots: switch modules off to see what costs what)
//     [--crowd 30]  (server-crowd: how many soldiers)
//     [--driver vulkan]  (windowed scenarios: the rendering driver; macOS defaults to vulkan,
//                         because Godot 4.7's Metal driver cannot time the GPU)
// `all` runs every scenario and the ablation and writes bench/report-<date>.md.
// Results and baselines live in bench/ (git-ignored): timings mean nothing across machines.
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { cpus, tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { arch, argv, exit, platform } from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { ablationDeltas, budgetLine, compare, parseBaseline, moduleCosts, netCosts, parseBenchArgs, parsePerfLog, passesLine, renderingDriver, serverCost, serverLine, summarise, table, worstSpikes, zoneCosts, type BenchArgs, type Summary } from "./lib/bench.ts";
import { renderReport, type Failure, type ScenarioResult } from "./lib/bench-report.ts";
import { localGodot } from "./lib/godot.ts";
import { summariseReport } from "./lib/report.ts";
import { run } from "./lib/proc.ts";
import { benchmarkArgs, rangeArgs } from "./lib/range.ts";

const root = resolve(import.meta.dirname, "..");
const godot = localGodot(root);
const outDir = join(root, "bench");
// Loading, building the first chunks and the bot getting going are not what we measure.
const WARMUP_SECONDS = 10;
// The game quits after this many frames (--net-report-after); about a minute at 60 fps.
const RUN_FRAMES = 3600;
// A windowed run too slow to get there is stopped after this long instead: its samples are
// on disk already, and a frame rate that low is the finding.
const RUN_SECONDS = 150;
const BOT_CLIENTS = 6;
const CROWD_CLIENTS = 4;
const TOP_ZONES = 12;
const TOP_MODULES = 8;
const TOP_SPIKES = 6;
// The solo server quits once its client has gone; give it this long to write its last lines.
const SERVER_EXIT_MS = 1500;

// The scenario --ablate reruns, and what each rerun switches off.
const ABLATE_SCENARIO = "solo-city";
const ABLATIONS: readonly [string, string[]][] = [
	["characters off", ["--flags=enemies:off"]],
	["shadows off", ["--no-shadows"]],
	["street lights off", ["--flags=lights:off"]],
	["city off (and its walk)", ["--flags=city:off"]],
	["half render scale", ["--render-scale=0.5"]],
];

interface Logs {
	// What the scenario measures: the client's log, or the dedicated server's.
	perf: string;
	// A windowed solo game's server.
	server: string;
}

interface Scenario {
	what: string;
	run: (logs: Logs, extra: readonly string[]) => Promise<void>;
}

let opts: BenchArgs;
let driver: string | undefined;

// A windowed solo game driven by a bot, with the perf module writing to `logs.perf` and its
// solo server to `logs.server`. `selfTimed` runs end themselves (the benchmark quits once its
// results are written), so they get no frame count to stop at.
async function windowed(name: string, userArgs: readonly string[], logs: Logs, extra: readonly string[], selfTimed = false): Promise<void> {
	const engine = driver === undefined ? [] : ["--rendering-driver", driver];
	const stop = selfTimed ? [] : [`--net-report-after=${RUN_FRAMES}`];
	const r = await run(godot, [...engine, "--path", root, "--", "--solo", ...userArgs, ...extra, "--uncapped", "--perf-spike-ms=20", ...stop, `--perf-log=${logs.perf}`, `--server-perf-log=${logs.server}`], { cwd: root, timeoutMs: RUN_SECONDS * 1000 });
	if (r.timedOut) console.log(`  ${name}: stopped after ${RUN_SECONDS} s, before ${RUN_FRAMES} frames (under ${(RUN_FRAMES / RUN_SECONDS).toFixed(0)} fps)`);
	await delay(SERVER_EXIT_MS);
}

const SCENARIOS: Record<string, Scenario> = {
	"solo-walk": {
		what: "windowed solo game, a bot walks the road and shoots (client rendering)",
		run: (logs, extra) => windowed("solo-walk", ["--bot=walk", "--no-save"], logs, extra),
	},
	"solo-drive": {
		what: "windowed solo game, a bot drives the car down the road (terrain and scenery streaming, car physics)",
		run: (logs, extra) => windowed("solo-drive", ["--bot=drive", "--no-save"], logs, extra),
	},
	"solo-city": {
		what: "windowed solo game starting in the city, a bot walks the ring of avenues round the square (the heaviest place to render: buildings, lamps, trees, guards)",
		run: (logs, extra) => windowed("solo-city", ["--start=city", "--bot=city", "--no-save"], logs, extra),
	},
	"solo-deaths": {
		what: "windowed solo game, squads land in front of the player and are killed one a second (what a soldier appearing and dying costs on screen)",
		run: (logs, extra) => windowed("solo-deaths", ["--bench=deaths", "--no-save"], logs, extra),
	},
	benchmark: {
		what: "the in-game benchmark players run from the menu: solo in the city, the city bot walks while squads land and die in front of the player (modules/benchmark); prints its own results too",
		run: async (logs, extra) => {
			const out = logs.perf.replace(/perf\.ndjson$/, "benchmark.json");
			await windowed("benchmark", [...benchmarkArgs(root), `--benchmark-out=${out}`], logs, extra, true);
			if (!existsSync(out)) throw new Error("benchmark wrote no results (did the run finish?)");
			for (const line of summariseReport({ kind: "benchmark", benchmark: JSON.parse(readFileSync(out, "utf8")) }).filter((l) => l.startsWith("  benchmark") || l.startsWith("    hitch"))) console.log(line);
		},
	},
	"range-destroy": {
		what: "windowed solo game on the test range, the range bot shoots and blasts each building in turn (destruction cost: remeshing, debris, collapse)",
		run: (logs, extra) => windowed("range-destroy", [...rangeArgs(root), "--bot=range"], logs, extra),
	},
	"server-bots": {
		what: `headless dedicated server with ${BOT_CLIENTS} bot clients (server cost)`,
		run: async (logs) => {
			const port = 7795;
			const base = ["--headless", "--path", root, "--"];
			// --server-flags car:off,enemies:off narrows down what costs what.
			const extra = opts.serverFlags === undefined ? [] : [`--flags=${opts.serverFlags}`];
			const server = run(godot, [...base, `--server=${port}`, "--no-save", "--uncapped", "--perf-spike-ms=20", ...extra, `--net-report-after=${RUN_FRAMES + 600}`, `--perf-log=${logs.perf}`], { cwd: root, timeoutMs: 300_000 });
			await delay(4000);
			const clients = Array.from({ length: BOT_CLIENTS }, (_, i) =>
				run(godot, [...base, `--connect=127.0.0.1:${port}`, i === 0 ? "--bot=drive" : "--bot=walk", `--net-report-after=${RUN_FRAMES}`, `--name=bench${i}`], { cwd: root, timeoutMs: 300_000 }),
			);
			const results = await Promise.all([server, ...clients]);
			if (results.some((r) => r.timedOut)) throw new Error("server-bots timed out");
		},
	},
	"server-crowd": {
		what: `headless dedicated server, ${CROWD_CLIENTS} bot clients and --crowd soldiers (default 30) spread over the map (server and network cost per soldier)`,
		run: async (logs) => {
			const port = 7796;
			const base = ["--headless", "--path", root, "--"];
			// Not --uncapped: synchronizers send once a frame, so an uncapped server would send many
			// times what a real one does. Server CPU comes from the per-tick physics and zones.
			const server = run(godot, [...base, `--server=${port}`, "--no-save", "--perf-spike-ms=20", `--crowd=${opts.crowd}`, `--net-report-after=${RUN_FRAMES + 600}`, `--perf-log=${logs.perf}`], { cwd: root, timeoutMs: 400_000 });
			await delay(4000);
			const clients = Array.from({ length: CROWD_CLIENTS }, (_, i) =>
				run(godot, [...base, `--connect=127.0.0.1:${port}`, i === 0 ? "--bot=drive" : "--bot=walk", `--net-report-after=${RUN_FRAMES}`, `--name=crowd${i}`], { cwd: root, timeoutMs: 400_000 }),
			);
			const results = await Promise.all([server, ...clients]);
			if (results.some((r) => r.timedOut)) throw new Error("server-crowd timed out");
		},
	},
};

interface Measured {
	result: ScenarioResult;
	// The logs, for keeping beside the summary.
	perfText: string;
	serverText: string | undefined;
}

// Runs one scenario (with `extra` user arguments) and reads its logs. Throws when it wrote
// nothing usable.
async function measure(name: string, extra: readonly string[]): Promise<Measured> {
	const scenario = SCENARIOS[name]!;
	const work = mkdtempSync(join(tmpdir(), "slopocalypse-bench-"));
	try {
		const logs = { perf: join(work, "perf.ndjson").replaceAll("\\", "/"), server: join(work, "server.ndjson").replaceAll("\\", "/") };
		await scenario.run(logs, extra);
		if (!existsSync(logs.perf)) throw new Error(`${name} wrote no perf log (is the perf module on?)`);
		const perfText = readFileSync(logs.perf, "utf8");
		const records = parsePerfLog(perfText);
		const summary = summarise(records, WARMUP_SECONDS);
		if (summary.samples === 0) throw new Error(`${name}: no samples after the ${WARMUP_SECONDS} s warm-up`);
		const serverText = existsSync(logs.server) ? readFileSync(logs.server, "utf8") : undefined;
		// A dedicated server scenario's own log is the server's.
		const serverRecords = serverText !== undefined ? parsePerfLog(serverText) : summary.driver === "" ? records : [];
		return {
			result: {
				name,
				what: scenario.what,
				summary,
				baseline: undefined,
				regressions: [],
				zones: zoneCosts(records, WARMUP_SECONDS),
				modules: moduleCosts(records, WARMUP_SECONDS),
				spikes: worstSpikes(perfText, WARMUP_SECONDS, TOP_SPIKES),
				net: netCosts(records, WARMUP_SECONDS),
				server: serverCost(serverRecords, WARMUP_SECONDS),
			},
			perfText,
			serverText,
		};
	} finally {
		rmSync(work, { recursive: true, force: true });
	}
}

function print(res: ScenarioResult): void {
	const s = res.summary;
	console.log(`  ${budgetLine(s)}`);
	if (s.driver !== "") console.log(`  ${passesLine(s)}`);
	console.log(`  nodes' physics per tick: ${s.physics_ms} ms; worst moment per second (Godot's peak): physics ${s.physics_peak_ms} ms`);
	if (res.server !== undefined) console.log(`  server${s.driver === "" ? "" : " (solo)"}: ${serverLine(res.server)}`);
	if (res.modules.length > 0) console.log(`  modules (us per frame): ${res.modules.slice(0, TOP_MODULES).map(([m, us]) => `${m} ${us}`).join(", ")}`);
	console.log("  most expensive zones (microseconds per frame):");
	for (const [zone, us] of res.zones.slice(0, TOP_ZONES)) console.log(`    ${zone.padEnd(38)} ${us.toFixed(1).padStart(8)}`);
	if (res.spikes.length > 0) console.log("  worst hitches (frame ms at second t: zones in ms, shader pipelines compiled):");
	for (const sp of res.spikes) {
		const ran = Object.entries(sp.zones).sort((a, b) => b[1] - a[1]).map(([z, ms]) => `${z} ${ms}`).join(", ");
		const compiles = Object.entries(sp.compiles).map(([k, c]) => `${c} ${k}`).join(", ");
		console.log(`    ${sp.ms.toFixed(1).padStart(7)} ms at ${sp.t.toFixed(1)} s: ${ran || "no zones"}${compiles === "" ? "" : `; compiled ${compiles}`}`);
	}
	if (res.net !== undefined) {
		console.log(`  sent to each client: ${(res.net.outPerPeer / 1024).toFixed(1)} KB/s; by source (estimated, KB/s across all clients):`);
		for (const [source, bytes] of res.net.sources) console.log(`    ${source.padEnd(38)} ${(bytes / 1024).toFixed(1).padStart(8)}`);
	}
}

function errorText(err: unknown): string {
	return err instanceof Error ? err.message : String(err);
}

function machine(): string {
	const cpu = cpus();
	return `${platform} ${arch}, ${cpu[0]?.model ?? "unknown CPU"}, ${cpu.length} threads`;
}

function commit(): string {
	try {
		return execFileSync("git", ["rev-parse", "--short", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
	} catch {
		return "unknown";
	}
}

async function main(): Promise<void> {
	if (!existsSync(godot)) throw new Error("Godot missing: run node tools/get-godot.ts");
	opts = parseBenchArgs(argv.slice(2), Object.keys(SCENARIOS));
	driver = renderingDriver(platform, opts.driver);
	mkdirSync(outDir, { recursive: true });
	if (driver !== undefined) console.log(`windowed scenarios render with ${driver}${opts.driver === undefined ? " (on macOS Godot's Metal driver cannot time the GPU; players there run Metal)" : ""}`);

	const stamp = new Date().toISOString().replaceAll(":", "-").slice(0, 19);
	const results: ScenarioResult[] = [];
	const failures: Failure[] = [];
	let regressions = 0;
	for (const name of opts.scenarios) {
		console.log(`\n${name}: ${SCENARIOS[name]!.what}`);
		let measured: Measured;
		try {
			measured = await measure(name, []);
		} catch (err) {
			// One broken scenario must not cost the rest of a long run.
			console.log(`  FAILED: ${errorText(err)}`);
			failures.push({ name, error: errorText(err) });
			continue;
		}
		const res = measured.result;
		print(res);
		writeFileSync(join(outDir, `${name}-${stamp}.json`), JSON.stringify(res, null, 2) + "\n");
		// The raw logs too, for digging into a run afterwards.
		writeFileSync(join(outDir, `${name}-${stamp}.ndjson`), measured.perfText);
		if (measured.serverText !== undefined) writeFileSync(join(outDir, `${name}-${stamp}.server.ndjson`), measured.serverText);
		const baselineFile = join(outDir, `${name}.baseline.json`);
		const baseline = existsSync(baselineFile) ? parseBaseline(readFileSync(baselineFile, "utf8")) : undefined;
		if (existsSync(baselineFile) && baseline === undefined) console.log(`  ${baselineFile} is not a baseline; saving this run in its place`);
		res.baseline = baseline;
		if (baseline !== undefined) {
			res.regressions = compare(res.summary, baseline, opts.tolerance);
			for (const r of res.regressions) {
				regressions++;
				console.log(`  REGRESSION ${r.metric}: ${r.baseline} -> ${r.now} (+${(r.change * 100).toFixed(1)}%)`);
			}
		}
		if (opts.saveBaseline || baseline === undefined) {
			writeFileSync(baselineFile, JSON.stringify(res.summary, null, 2) + "\n");
			console.log(`  saved as this machine's baseline: ${baselineFile}`);
		}
		results.push(res);
	}
	if (results.length > 0) console.log("\n" + table(results.map((r): [string, Summary, Partial<Summary> | undefined] => [r.name, r.summary, r.baseline])));

	const ablation = opts.ablate ? await ablate(results) : undefined;
	if (opts.ablate && ablation === undefined) failures.push({ name: "ablation", error: `the full ${ABLATE_SCENARIO} run failed` });
	if (opts.all) {
		const file = join(outDir, `report-${stamp}.md`);
		writeFileSync(file, renderReport({ date: stamp, machine: machine(), commit: commit(), results, failures, ablation }));
		console.log(`\nreport: ${file}`);
	}
	// The ablation counts too: a variant that did not run leaves a hole in the table.
	const ablationFailed = opts.ablate && (ablation === undefined || ablation.failures.length > 0);
	if (failures.length > 0) console.log(`\n${failures.length} scenario(s) failed: ${failures.map((f) => f.name).join(", ")}`);
	if (ablationFailed) console.log("\nthe ablation did not run in full");
	if (regressions > 0) console.log(`\n${regressions} regression(s) beyond ${(opts.tolerance * 100).toFixed(0)}%`);
	if (failures.length > 0 || ablationFailed || regressions > 0) exit(1);
}

// Reruns ABLATE_SCENARIO with each switch in ABLATIONS and prints what each saves against the
// full run (this invocation's, or a fresh one).
async function ablate(results: readonly ScenarioResult[]): Promise<{ scenario: string; full: Summary; deltas: ReturnType<typeof ablationDeltas>; failures: Failure[] } | undefined> {
	console.log(`\nablation: ${ABLATE_SCENARIO} with one thing off at a time`);
	let full = results.find((r) => r.name === ABLATE_SCENARIO)?.summary;
	const failures: Failure[] = [];
	if (full === undefined) {
		try {
			full = (await measure(ABLATE_SCENARIO, [])).result.summary;
		} catch (err) {
			console.log(`  FAILED: the full run: ${errorText(err)}`);
			return undefined;
		}
	}
	console.log(`  full: ${budgetLine(full)}`);
	const variants: [string, Summary][] = [];
	for (const [name, args] of ABLATIONS) {
		try {
			const s = (await measure(ABLATE_SCENARIO, args)).result.summary;
			console.log(`  ${name} (${args.join(" ")}): ${budgetLine(s)}`);
			variants.push([name, s]);
		} catch (err) {
			console.log(`  ${name}: FAILED: ${errorText(err)}`);
			failures.push({ name, error: errorText(err) });
		}
	}
	const deltas = ablationDeltas(full, variants);
	console.log("  what each costs (variant minus full run, ms per frame; negative is the saving):");
	console.log(`    ${"off".padEnd(26)} ${"frame".padStart(7)} ${"share".padStart(6)} ${"scripts".padStart(8)} ${"physics".padStart(8)} ${"render".padStart(7)} ${"other".padStart(6)} ${"gpu".padStart(7)} ${"draws".padStart(7)}`);
	for (const d of deltas) {
		console.log(`    ${d.name.padEnd(26)} ${d.frame_ms.toFixed(2).padStart(7)} ${`${(d.share * 100).toFixed(0)}%`.padStart(6)} ${d.scripts_ms.toFixed(2).padStart(8)} ${d.physics_ms.toFixed(2).padStart(8)} ${d.render_ms.toFixed(2).padStart(7)} ${d.other_ms.toFixed(2).padStart(6)} ${(d.gpu_ms === null ? "untimed" : d.gpu_ms.toFixed(2)).padStart(7)} ${String(d.draw_calls).padStart(7)}`);
	}
	return { scenario: ABLATE_SCENARIO, full, deltas, failures };
}

try {
	await main();
} catch (err) {
	console.error(errorText(err));
	exit(1);
}

// Benchmarks: runs fixed scenarios, reads the perf log each writes, and compares with this
// machine's baseline. Not part of the gate (timings are too noisy on shared machines).
//   node tools/bench.ts [solo-walk] [solo-drive] [range-destroy] [server-bots] [--save-baseline] [--tolerance 0.15]
//     [--server-flags car:off,enemies:off]  (server-bots: switch modules off to see what costs what)
// Results and baselines live in bench/ (git-ignored): timings mean nothing across machines.
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { argv, exit } from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { compare, parsePerfLog, summarise, table, zoneCosts, type Summary } from "./lib/bench.ts";
import { localGodot } from "./lib/godot.ts";
import { run } from "./lib/proc.ts";
import { rangeArgs } from "./lib/range.ts";

const root = resolve(import.meta.dirname, "..");
const godot = localGodot(root);
const outDir = join(root, "bench");
// Loading, building the first chunks and the bot getting going are not what we measure.
const WARMUP_SECONDS = 10;
// The game quits after this many frames (--net-report-after); about a minute at 60 fps.
const RUN_FRAMES = 3600;
const BOT_CLIENTS = 6;
const TOP_ZONES = 12;

interface Scenario {
	what: string;
	run: (perfLog: string) => Promise<void>;
}

const SCENARIOS: Record<string, Scenario> = {
	"solo-walk": {
		what: "windowed solo game, a bot walks the road and shoots (client rendering)",
		run: async (perfLog) => {
			const r = await run(godot, ["--path", root, "--", "--solo", "--bot=walk", "--no-save", "--uncapped", "--perf-spike-ms=20", `--net-report-after=${RUN_FRAMES}`, `--perf-log=${perfLog}`], { cwd: root, timeoutMs: 240_000 });
			if (r.timedOut) throw new Error("solo-walk timed out");
		},
	},
	"solo-drive": {
		what: "windowed solo game, a bot drives the car down the road (terrain and scenery streaming, car physics)",
		run: async (perfLog) => {
			const r = await run(godot, ["--path", root, "--", "--solo", "--bot=drive", "--no-save", "--uncapped", "--perf-spike-ms=20", `--net-report-after=${RUN_FRAMES}`, `--perf-log=${perfLog}`], { cwd: root, timeoutMs: 240_000 });
			if (r.timedOut) throw new Error("solo-drive timed out");
		},
	},
	"range-destroy": {
		what: "windowed solo game on the test range, the range bot shoots and blasts each building in turn (destruction cost: remeshing, debris, collapse)",
		run: async (perfLog) => {
			const r = await run(godot, ["--path", root, "--", "--solo", ...rangeArgs(root), "--bot=range", "--uncapped", "--perf-spike-ms=20", `--net-report-after=${RUN_FRAMES}`, `--perf-log=${perfLog}`], { cwd: root, timeoutMs: 240_000 });
			if (r.timedOut) throw new Error("range-destroy timed out");
		},
	},
	"server-bots": {
		what: `headless dedicated server with ${BOT_CLIENTS} bot clients (server cost)`,
		run: async (perfLog) => {
			const port = 7795;
			const base = ["--headless", "--path", root, "--"];
			// --server-flags car:off,enemies:off narrows down what costs what.
			const flags = arg("server-flags");
			const extra = flags === undefined ? [] : [`--flags=${flags}`];
			const server = run(godot, [...base, `--server=${port}`, "--no-save", "--uncapped", "--perf-spike-ms=20", ...extra, `--net-report-after=${RUN_FRAMES + 600}`, `--perf-log=${perfLog}`], { cwd: root, timeoutMs: 300_000 });
			await delay(4000);
			const clients = Array.from({ length: BOT_CLIENTS }, (_, i) =>
				run(godot, [...base, `--connect=127.0.0.1:${port}`, i === 0 ? "--bot=drive" : "--bot=walk", `--net-report-after=${RUN_FRAMES}`, `--name=bench${i}`], { cwd: root, timeoutMs: 300_000 }),
			);
			const results = await Promise.all([server, ...clients]);
			if (results.some((r) => r.timedOut)) throw new Error("server-bots timed out");
		},
	},
};

function arg(name: string): string | undefined {
	const i = argv.indexOf(`--${name}`);
	return i >= 0 ? argv[i + 1] : undefined;
}

async function main(): Promise<void> {
	if (!existsSync(godot)) throw new Error("Godot missing: run node tools/get-godot.ts");
	const asked = argv.slice(2).filter((a) => !a.startsWith("--") && a !== arg("tolerance") && a !== arg("server-flags"));
	const names = asked.length > 0 ? asked : Object.keys(SCENARIOS);
	for (const n of names) if (!(n in SCENARIOS)) throw new Error(`unknown scenario ${n}; known: ${Object.keys(SCENARIOS).join(", ")}`);
	const tolerance = Number(arg("tolerance") ?? "0.15");
	const saveBaseline = argv.includes("--save-baseline");
	mkdirSync(outDir, { recursive: true });

	const rows: [string, Summary, Summary | undefined][] = [];
	let regressions = 0;
	for (const name of names) {
		const scenario = SCENARIOS[name]!;
		console.log(`\n${name}: ${scenario.what}`);
		const work = mkdtempSync(join(tmpdir(), "slopocalypse-bench-"));
		try {
			const perfLog = join(work, "perf.ndjson").replaceAll("\\", "/");
			await scenario.run(perfLog);
			if (!existsSync(perfLog)) throw new Error(`${name} wrote no perf log (is the perf module on?)`);
			const records = parsePerfLog(readFileSync(perfLog, "utf8"));
			const summary = summarise(records, WARMUP_SECONDS);
			if (summary.samples === 0) throw new Error(`${name}: no samples after the ${WARMUP_SECONDS} s warm-up`);
			const zones = zoneCosts(records, WARMUP_SECONDS);
			console.log(`  nodes' physics per tick: ${summary.physics_ms} ms; worst moment per second (Godot's peak): physics ${summary.physics_peak_ms} ms`);
			console.log("  most expensive zones (microseconds per frame):");
			for (const [zone, us] of zones.slice(0, TOP_ZONES)) console.log(`    ${zone.padEnd(38)} ${us.toFixed(1).padStart(8)}`);
			const stamp = new Date().toISOString().replaceAll(":", "-").slice(0, 19);
			writeFileSync(join(outDir, `${name}-${stamp}.json`), JSON.stringify({ ...summary, zones }, null, 2) + "\n");
			// The raw log too, for digging into a run afterwards.
			copyFileSync(perfLog, join(outDir, `${name}-${stamp}.ndjson`));
			const baselineFile = join(outDir, `${name}.baseline.json`);
			const baseline: Summary | undefined = existsSync(baselineFile) ? JSON.parse(readFileSync(baselineFile, "utf8")) : undefined;
			rows.push([name, summary, baseline]);
			if (baseline !== undefined) {
				for (const r of compare(summary, baseline, tolerance)) {
					regressions++;
					console.log(`  REGRESSION ${r.metric}: ${r.baseline} -> ${r.now} (+${(r.change * 100).toFixed(1)}%)`);
				}
			}
			if (saveBaseline || baseline === undefined) {
				writeFileSync(baselineFile, JSON.stringify(summary, null, 2) + "\n");
				console.log(`  saved as this machine's baseline: ${baselineFile}`);
			}
		} finally {
			rmSync(work, { recursive: true, force: true });
		}
	}
	console.log("\n" + table(rows));
	if (regressions > 0) {
		console.log(`\n${regressions} regression(s) beyond ${(tolerance * 100).toFixed(0)}%`);
		exit(1);
	}
}

try {
	await main();
} catch (err) {
	console.error(err instanceof Error ? err.message : err);
	exit(1);
}

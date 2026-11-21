import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { availableParallelism, tmpdir } from "node:os";
import { join, relative, sep } from "node:path";
import { platform } from "node:process";
import { failureLines, scanLog, testSummary } from "./log-scan.ts";
import { run, type ProcResult } from "./proc.ts";

// Known harmless lines. gdUnit4 points the remote debugger at port 0 on purpose so a
// parse error cannot drop Godot into its interactive debug> prompt.
export const GODOT_NOISE: readonly RegExp[] = [
	/remote port number must be between 1 and 65535/,
	/Remote Debugger: Unable to connect to host '127\.0\.0\.1:0'/,
	/Pages in use exist at exit in PagedAllocator/,
];

export interface StepResult {
	ok: boolean;
	detail: string;
}

const toRes = (root: string, path: string): string => "res://" + relative(root, path).split(sep).join("/");

// Godot caches the extension list in .godot/ and errors on a deleted module's .gdextension
// until a second import, so write the list from what actually exists, as Godot itself does.
export function refreshExtensionList(root: string): void {
	const found: string[] = [];
	const walk = (dir: string): void => {
		for (const name of readdirSync(dir)) {
			if (name.startsWith(".") || name === "node_modules" || name === "target" || name === "tools") continue;
			const full = join(dir, name);
			if (statSync(full).isDirectory()) walk(full);
			else if (name.endsWith(".gdextension")) found.push(toRes(root, full));
		}
	};
	walk(root);
	mkdirSync(join(root, ".godot"), { recursive: true });
	writeFileSync(join(root, ".godot", "extension_list.cfg"), found.map((p) => p + "\n").join(""));
}

// Runs `step`, and once more if it fails. For steps where the engine itself crashes now and
// then: a real failure fails again, and the pass still says it needed a second go.
export async function retryOnce(step: () => Promise<StepResult>): Promise<StepResult> {
	const first = await step();
	if (first.ok) return first;
	const second = await step();
	if (!second.ok) return second;
	return { ok: true, detail: `${second.detail} (retried after: ${first.detail.split("\n")[0]})` };
}

// Godot's headless import sometimes exits -1 with a thread error on CI runners
// (`propagate_notification()` from the wrong thread), and passes when run again.
export function godotImport(godot: string, root: string): Promise<StepResult> {
	return retryOnce(() => importOnce(godot, root));
}

async function importOnce(godot: string, root: string): Promise<StepResult> {
	refreshExtensionList(root);
	const r = await run(godot, ["--headless", "--path", root, "--import"], { cwd: root, timeoutMs: 300_000 });
	const problems = scanLog(r.output, GODOT_NOISE);
	if (r.timedOut) return { ok: false, detail: "import timed out" };
	if (r.code !== 0 || problems.length > 0) {
		return { ok: false, detail: [`import exit ${r.code}`, ...problems].join("\n") };
	}
	return { ok: true, detail: "clean" };
}

// One Godot process compiles every script inside the running project, so autoload names
// resolve. `--check-only` compiles in isolation and rejects any script that uses an autoload.
export async function checkScripts(godot: string, root: string, files: readonly string[]): Promise<StepResult> {
	if (files.length === 0) return { ok: true, detail: "no scripts to check" };
	const args = ["--headless", "--path", root, "-s", "res://tools/gd/check_scripts.gd", "--", ...files.map((f) => toRes(root, f))];
	const r = await run(godot, args, { cwd: root, timeoutMs: 120_000 });
	const problems = scanLog(r.output, GODOT_NOISE);
	if (r.timedOut) return { ok: false, detail: "script check timed out" };
	if (r.code !== 0 || problems.length > 0) {
		return { ok: false, detail: problems.join("\n") || `exit ${r.code}` };
	}
	return { ok: true, detail: `${files.length} script(s) compile` };
}

// Each gdUnit process runs its suites one after another, and the full suite took over 20
// minutes on a 4-core CI runner, so the suites are split across processes. More than this
// many fight over cores and memory more than they gain.
const MAX_SHARDS = 6;
// Estimates for a suite with no recorded time: scenario suites run physics for seconds.
const GUESS_SCENARIO_SECONDS = 5;
const GUESS_SECONDS = 1;
// Times from the last runs on this machine (git-ignored) win over the committed ones, which
// CI uses; refresh the committed file by copying the local one over it now and then.
const LOCAL_DURATIONS = "tests/reports/durations.json";
export const COMMITTED_DURATIONS = "tools/test-durations.json";

export interface Suite {
	path: string;
	seconds: number;
}

// gdUnit's own convention, which every suite here follows: test_*.gd.
export function listSuites(testDirs: readonly string[]): string[] {
	const found: string[] = [];
	const walk = (dir: string): void => {
		for (const name of readdirSync(dir)) {
			const full = join(dir, name);
			if (statSync(full).isDirectory()) walk(full);
			else if (/^test_.*\.gd$/.test(name)) found.push(full);
		}
	};
	for (const dir of testDirs) if (existsSync(dir)) walk(dir);
	return found.sort();
}

export function guessSeconds(resPath: string, known: Readonly<Record<string, number>>): number {
	return known[resPath] ?? (resPath.includes("/scenario/") ? GUESS_SCENARIO_SECONDS : GUESS_SECONDS);
}

export function shardCount(cpus: number, suites: number): number {
	return Math.max(1, Math.min(cpus, MAX_SHARDS, suites));
}

// Longest first, each to the least loaded shard: close to even without knowing more.
export function planShards(suites: readonly Suite[], count: number): string[][] {
	const shards = Array.from({ length: count }, () => ({ total: 0, paths: [] as string[] }));
	const order = [...suites].sort((a, b) => b.seconds - a.seconds || a.path.localeCompare(b.path));
	for (const suite of order) {
		let least = shards[0]!;
		for (const shard of shards) if (shard.total < least.total) least = shard;
		least.total += suite.seconds;
		least.paths.push(suite.path);
	}
	return shards.map((s) => s.paths).filter((p) => p.length > 0);
}

// Suite times from a gdUnit results.xml, by res:// path.
export function suiteTimes(xml: string): Record<string, number> {
	const out: Record<string, number> = {};
	for (const m of xml.matchAll(/<testsuite\b[^>]*>/g)) {
		const tag = m[0];
		const name = /\bname="([^"]+)"/.exec(tag)?.[1];
		const pkg = /\bpackage="([^"]+)"/.exec(tag)?.[1];
		const time = /\btime="([\d.]+)"/.exec(tag)?.[1];
		if (name === undefined || pkg === undefined || time === undefined) continue;
		out[`res://${pkg}/${name}.gd`] = Number(time);
	}
	return out;
}

// Godot puts user:// under the OS's per-user data folder, which each OS lets an environment
// variable move. Shards each get their own, so one cannot delete what another is using
// (gdUnit empties user://tmp after every suite) or read another's test files.
export function userDirEnv(os: NodeJS.Platform, dir: string): Record<string, string> {
	if (os === "win32") return { APPDATA: dir };
	if (os === "darwin") return { HOME: dir };
	return { XDG_DATA_HOME: dir };
}

function readDurations(path: string): Record<string, number> {
	if (!existsSync(path)) return {};
	try {
		const parsed: unknown = JSON.parse(readFileSync(path, "utf8"));
		if (typeof parsed !== "object" || parsed === null) return {};
		const out: Record<string, number> = {};
		for (const [k, v] of Object.entries(parsed)) if (typeof v === "number") out[k] = v;
		return out;
	} catch {
		return {};
	}
}

function newestReport(dir: string): string | undefined {
	if (!existsSync(dir)) return undefined;
	const numbered = readdirSync(dir)
		.map((n) => /^report_(\d+)$/.exec(n))
		.filter((m): m is RegExpExecArray => m !== null)
		.sort((a, b) => Number(b[1]) - Number(a[1]));
	const name = numbered[0]?.[0];
	return name === undefined ? undefined : join(dir, name, "results.xml");
}

interface ShardRun {
	suites: number;
	result: ProcResult;
	times: Record<string, number>;
}

async function runShard(godot: string, root: string, files: readonly string[], index: number): Promise<ShardRun> {
	const reports = join(root, "tests", "reports", `shard-${index}`);
	const userDir = mkdtempSync(join(tmpdir(), "slopocalypse-gdunit-"));
	const args = [
		"--headless",
		"--path",
		root,
		"-s",
		"-d",
		"--remote-debug",
		"tcp://127.0.0.1:0",
		"res://addons/gdUnit4/bin/GdUnitCmdTool.gd",
		// Input events don't reach headless Godot; our tests drive intent components instead.
		"--ignoreHeadlessMode",
		"-rd",
		toRes(root, reports),
		...files.flatMap((f) => ["-a", toRes(root, f)]),
	];
	try {
		// A shard runs a few minutes; the limit only catches a hang.
		const result = await run(godot, args, { cwd: root, timeoutMs: 1_200_000, env: { ...process.env, ...userDirEnv(platform, userDir) } });
		const xml = newestReport(reports);
		const times = xml !== undefined && existsSync(xml) ? suiteTimes(readFileSync(xml, "utf8")) : {};
		return { suites: files.length, result, times };
	} finally {
		rmSync(userDir, { recursive: true, force: true });
	}
}

export async function runGdUnit(godot: string, root: string, testDirs: readonly string[]): Promise<StepResult> {
	if (testDirs.length === 0) return { ok: true, detail: "no test directories" };
	const files = listSuites(testDirs);
	if (files.length === 0) return { ok: true, detail: "no test suites" };
	const localDurations = join(root, LOCAL_DURATIONS);
	const known = { ...readDurations(join(root, COMMITTED_DURATIONS)), ...readDurations(localDurations) };
	const suites = files.map((path) => ({ path, seconds: guessSeconds(toRes(root, path), known) }));
	const shards = planShards(suites, shardCount(availableParallelism(), suites.length));
	const runs = await Promise.all(shards.map((paths, i) => runShard(godot, root, paths, i)));

	const lines: string[] = [];
	const failed: string[] = [];
	let cases = 0;
	const times: Record<string, number> = { ...readDurations(localDurations) };
	runs.forEach((shard, i) => {
		const r = shard.result;
		const name = runs.length > 1 ? `shard ${i + 1}/${runs.length} (${shard.suites} suites): ` : "";
		const summary = testSummary(r.output);
		const problems = scanLog(r.output, GODOT_NOISE);
		const before = lines.length;
		if (r.timedOut) lines.push(`${name}test run timed out`);
		if (summary === undefined) lines.push(`${name}no test summary in output (exit ${r.code})`);
		else {
			cases += summary.cases;
			if (summary.errors + summary.failures > 0) lines.push(`${name}${summary.failures} failure(s), ${summary.errors} error(s)`);
			if (r.code !== 0 && summary.errors + summary.failures === 0) lines.push(`${name}exit ${r.code}`);
		}
		if (problems.length > 0) lines.push(`${name}unexpected error lines:`, ...problems.map((p) => "  " + p));
		if (lines.length > before) failed.push(...failureLines(r.output));
		// Self-test fixtures live in fresh hidden folders; their times would only pile up.
		for (const [path, secs] of Object.entries(shard.times)) if (!path.includes("/.")) times[path] = Math.round(secs * 10) / 10;
	});
	mkdirSync(join(root, "tests", "reports"), { recursive: true });
	writeFileSync(localDurations, JSON.stringify(Object.fromEntries(Object.entries(times).sort(([a], [b]) => a.localeCompare(b))), null, "\t") + "\n");
	if (lines.length > 0) return { ok: false, detail: [...lines, ...failed.slice(0, 60)].join("\n") };
	return { ok: true, detail: `${cases} test case(s) passed${runs.length > 1 ? ` in ${runs.length} parallel runs` : ""}` };
}

// Directories named "tests" anywhere outside addons/ and hidden folders; "unit" subfolders for the fast check.
export function findTestDirs(root: string, mode: "fast" | "full"): string[] {
	const found: string[] = [];
	const walk = (dir: string): void => {
		for (const name of readdirSync(dir)) {
			if (name.startsWith(".") || name === "addons" || name === "node_modules" || name === "tools") continue;
			const full = join(dir, name);
			if (!statSync(full).isDirectory()) continue;
			if (name === "tests") {
				const unit = join(full, "unit");
				if (mode === "full") found.push(full);
				else if (existsSync(unit)) found.push(unit);
				continue;
			}
			walk(full);
		}
	};
	walk(root);
	return found;
}

// Runs the real main scene for a few frames and checks the boot log line. This is what
// proves a module can be switched off (or deleted) without breaking startup.
// The game starts its own solo server, which would otherwise sit out its 30 s wait for a
// player that already left, holding the output open; only the game's own boot counts here.
export async function bootGame(godot: string, root: string, userArgs: readonly string[], expect: RegExp): Promise<StepResult> {
	// --no-save: the solo server is killed with the game and must not be writing the player's world.
	const args = ["--headless", "--path", root, "--quit-after", "120", "--", "--no-save", ...userArgs];
	const r = await run(godot, args, { cwd: root, timeoutMs: 60_000, children: "kill" });
	const problems = scanLog(r.output, GODOT_NOISE);
	if (r.timedOut) return { ok: false, detail: "boot timed out" };
	if (r.code !== 0 || problems.length > 0) return { ok: false, detail: [`exit ${r.code}`, ...problems].join("\n") };
	const line = r.output.split(/\r?\n/).find((l) => l.includes("loaded modules:"));
	if (line === undefined || !expect.test(line)) {
		return { ok: false, detail: `expected boot line matching ${expect}, got: ${line ?? "(none)"}` };
	}
	return { ok: true, detail: line.trim() };
}

import { existsSync, mkdirSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { join, relative, sep } from "node:path";
import { scanLog, stripAnsi, testSummary } from "./log-scan.ts";
import { run } from "./proc.ts";

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

export async function godotImport(godot: string, root: string): Promise<StepResult> {
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

export async function runGdUnit(godot: string, root: string, testDirs: readonly string[]): Promise<StepResult> {
	if (testDirs.length === 0) return { ok: true, detail: "no test directories" };
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
		"res://tests/reports",
		...testDirs.flatMap((d) => ["-a", toRes(root, d)]),
	];
	const r = await run(godot, args, { cwd: root, timeoutMs: 600_000 });
	const summary = testSummary(r.output);
	const problems = scanLog(r.output, GODOT_NOISE);
	const lines: string[] = [];
	if (r.timedOut) lines.push("test run timed out");
	if (summary === undefined) lines.push(`no test summary in output (exit ${r.code})`);
	else if (summary.errors + summary.failures > 0) lines.push(`${summary.failures} failure(s), ${summary.errors} error(s)`);
	if (r.code !== 0 && summary !== undefined && summary.errors + summary.failures === 0) lines.push(`exit ${r.code}`);
	if (problems.length > 0) lines.push("unexpected error lines:", ...problems.map((p) => "  " + p));
	if (lines.length > 0) {
		const failed = stripAnsi(r.output)
			.split(/\r?\n/)
			.filter((l) => /FAILED|Parse Error|at '/.test(l))
			.slice(0, 20);
		return { ok: false, detail: [...lines, ...failed].join("\n") };
	}
	return { ok: true, detail: `${summary?.cases ?? 0} test case(s) passed` };
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
export async function bootGame(godot: string, root: string, userArgs: readonly string[], expect: RegExp): Promise<StepResult> {
	const args = ["--headless", "--path", root, "--quit-after", "30", ...(userArgs.length > 0 ? ["--", ...userArgs] : [])];
	const r = await run(godot, args, { cwd: root, timeoutMs: 60_000 });
	const problems = scanLog(r.output, GODOT_NOISE);
	if (r.timedOut) return { ok: false, detail: "boot timed out" };
	if (r.code !== 0 || problems.length > 0) return { ok: false, detail: [`exit ${r.code}`, ...problems].join("\n") };
	const line = r.output.split(/\r?\n/).find((l) => l.includes("loaded modules:"));
	if (line === undefined || !expect.test(line)) {
		return { ok: false, detail: `expected boot line matching ${expect}, got: ${line ?? "(none)"}` };
	}
	return { ok: true, detail: line.trim() };
}

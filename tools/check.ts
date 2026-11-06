// The gate. Fast mode while coding, --full before every commit and in CI.
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { argv, execPath, exit } from "node:process";
import { bootGame, checkScripts, findTestDirs, godotImport, runGdUnit, type StepResult } from "./lib/gate.ts";
import { localGodot } from "./lib/godot.ts";
import { run } from "./lib/proc.ts";

const root = resolve(import.meta.dirname, "..");
const full = argv.includes("--full");
const godot = localGodot(root);

function git(args: string[]): string[] {
	try {
		return execFileSync("git", args, { cwd: root, encoding: "utf8" }).split(/\r?\n/).filter(Boolean);
	} catch {
		return [];
	}
}

function gdScripts(): string[] {
	// tools/gd scripts run as the main loop; loading check_scripts.gd from itself segfaults Godot.
	const isOurs = (f: string): boolean => f.endsWith(".gd") && !f.startsWith("addons/") && !f.startsWith("tools/");
	if (full) {
		return [...git(["ls-files", "--cached", "--others", "--exclude-standard"])].filter(isOurs);
	}
	const base = git(["merge-base", "HEAD", "origin/main"])[0] ?? "HEAD";
	const changed = new Set([
		...git(["diff", "--name-only", "--diff-filter=ACMR", base]),
		...git(["ls-files", "--others", "--exclude-standard"]),
	]);
	return [...changed].filter(isOurs);
}

async function nodeStep(args: string[]): Promise<StepResult> {
	const r = await run(execPath, args, { cwd: root, timeoutMs: 300_000 });
	return r.code === 0 ? { ok: true, detail: "ok" } : { ok: false, detail: r.output.trim().split("\n").slice(-30).join("\n") };
}

const steps: [string, () => Promise<StepResult>][] = [
	["typescript", () => nodeStep([join(root, "node_modules/typescript/bin/tsc"), "--noEmit", "-p", root])],
	["tool tests", () => nodeStep(["--test", "tools/**/*.test.ts"])],
	["godot import", () => godotImport(godot, root)],
	["gdscript parse", () => checkScripts(godot, root, gdScripts().map((f) => join(root, f)))],
	["gdscript tests", () => runGdUnit(godot, root, findTestDirs(root, full ? "full" : "fast"))],
	["boot", () => bootGame(godot, root, [], /loaded modules: \S/)],
	["boot, optional off", () => bootGame(godot, root, ["--all-optional-off"], /loaded modules: \(none\)/)],
];
// Self-tests start Godot with gdUnit4, which needs the class cache that the import step builds.
if (full) steps.push(["gate self-tests", () => nodeStep(["--test", "tools/**/*.itest.ts"])]);

async function main(): Promise<void> {
	if (!existsSync(godot)) {
		console.error(`Godot not found at ${godot}. Run: node tools/get-godot.ts`);
		exit(1);
	}
	if (!existsSync(join(root, "node_modules/typescript"))) {
		console.error("Dev dependencies missing. Run: npm ci");
		exit(1);
	}
	console.log(`check (${full ? "full" : "fast"})`);
	const started = Date.now();
	let failed = 0;
	for (const [name, step] of steps) {
		const t = Date.now();
		const result = await step();
		const secs = ((Date.now() - t) / 1000).toFixed(1);
		console.log(`${result.ok ? "PASS" : "FAIL"}  ${name.padEnd(16)} ${secs}s  ${result.ok ? result.detail : ""}`);
		if (!result.ok) {
			failed++;
			console.log(result.detail.replace(/^/gm, "      "));
		}
	}
	const total = ((Date.now() - started) / 1000).toFixed(1);
	console.log(failed === 0 ? `\nAll checks passed in ${total}s` : `\n${failed} check(s) failed in ${total}s`);
	exit(failed === 0 ? 0 : 1);
}

main().catch((err: unknown) => {
	console.error(err);
	exit(1);
});

// The gate. Fast mode while coding, --full before every commit and merge.
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { argv, execPath, exit } from "node:process";
import { bootGame, checkScripts, findTestDirs, godotImport, runGdUnit, type StepResult } from "./lib/gate.ts";
import { localGodot } from "./lib/godot.ts";
import { run } from "./lib/proc.ts";
import { buildRust, hasRustCrates } from "./lib/rust.ts";
import { buildScenes } from "./lib/scenes.ts";
import { netSmoke, soloSmoke } from "./lib/net.ts";

const root = resolve(import.meta.dirname, "..");
const full = argv.includes("--full");
const godot = localGodot(root);

type Step = [string, () => Promise<StepResult>];

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
		// ls-files still lists tracked files deleted in the working tree.
		return git(["ls-files", "--cached", "--others", "--exclude-standard"]).filter((f) => isOurs(f) && existsSync(join(root, f)));
	}
	const base = git(["merge-base", "HEAD", "origin/main"])[0] ?? "HEAD";
	const changed = new Set([
		...git(["diff", "--name-only", "--diff-filter=ACMR", base]),
		...git(["ls-files", "--others", "--exclude-standard"]),
	]);
	return [...changed].filter(isOurs);
}

const tail = (output: string): string => output.trim().split(/\r?\n/).slice(-30).join("\n");

async function commandStep(cmd: string, args: string[], timeoutMs: number): Promise<StepResult> {
	const r = await run(cmd, args, { cwd: root, timeoutMs });
	return r.code === 0 ? { ok: true, detail: "ok" } : { ok: false, detail: tail(r.output) };
}

const rustSteps: Step[] = hasRustCrates(root)
	? [
			["rust fmt", () => commandStep("cargo", ["fmt", "--all", "--check"], 120_000)],
			["rust clippy", () => commandStep("cargo", ["clippy", "--workspace", "--all-targets", "--", "-D", "warnings"], 1_800_000)],
			["rust tests", () => commandStep("cargo", ["test", "--workspace"], 1_800_000)],
			// Godot loads the extensions during import, so they must be built first.
			["rust build", () => buildRust(root, false)],
		]
	: [];

const steps: Step[] = [
	["typescript", () => commandStep(execPath, [join(root, "node_modules/typescript/bin/tsc"), "--noEmit", "-p", root], 300_000)],
	["tool tests", () => commandStep(execPath, ["--test", "tools/**/*.test.ts"], 300_000)],
	...rustSteps,
	["godot import", () => godotImport(godot, root)],
	["gdscript parse", () => checkScripts(godot, root, gdScripts().map((f) => join(root, f)))],
	["gdscript tests", () => runGdUnit(godot, root, findTestDirs(root, full ? "full" : "fast"))],
	["boot", () => bootGame(godot, root, [], /loaded modules: \S/)],
	["boot, optional off", () => bootGame(godot, root, ["--all-optional-off"], /loaded modules: \(none\)/)],
];
// Rebuilding must not change any committed scene: a diff means a builder changed without
// regenerating, or someone hand-edited generated output.
if (full) {
	steps.push([
		"scenes up to date",
		async () => {
			const r = await buildScenes(godot, root);
			if (!r.ok) return r;
			return r.changed.length === 0
				? { ok: true, detail: r.detail }
				: { ok: false, detail: ["rebuilt scenes differ (now regenerated, review and commit):", ...r.changed].join("\n") };
		},
	]);
}
// A real dedicated server and two clients as separate processes.
if (full) steps.push(["net smoke", () => netSmoke(godot, root)], ["solo smoke", () => soloSmoke(godot, root)]);
// Self-tests start Godot with gdUnit4, which needs the class cache that the import step builds.
if (full) steps.push(["gate self-tests", () => commandStep(execPath, ["--test", "tools/**/*.itest.ts"], 300_000)]);

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
		console.log(`${result.ok ? "PASS" : "FAIL"}  ${name.padEnd(18)} ${secs.padStart(5)}s  ${result.ok ? result.detail : ""}`);
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

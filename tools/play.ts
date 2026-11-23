// Scripted playtests: runs modules/<id>/playtests/<scenario>.ts against a real session (a headless
// dedicated server and named windowed clients) and writes what happened to
// build/play/<scenario>/<time>/: report.json, report.md, review.md, shots/ and logs/.
//   node tools/play.ts <scenario> [--headless] [--keep] [--port N] [--timeout SECONDS]
//   node tools/play.ts --list
// --headless: clients without windows (state checks only; screenshots are not taken).
// --keep: leave the game running after the scenario, for a look through the debug API (MCP),
// until Ctrl-C. Not part of the gate: it opens windows. Hand review.md to a reviewer that has
// not seen the code (see .claude/skills/visual-review/SKILL.md).
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { argv, exit } from "node:process";
import { pathToFileURL } from "node:url";
import { localGodot } from "./lib/godot.ts";
import { freeUdpPort } from "./lib/net.ts";
import { finalStatus, reportMarkdown, reviewMarkdown, type Report, type Status } from "./lib/play-report.ts";
import { findScenarios, parsePlayArgs, PlayRun, Playtest, PlaytestSkip, preferredPort } from "./lib/play.ts";

const root = resolve(import.meta.dirname, "..");
const DEFAULT_TIMEOUT_S = 600;

async function main(): Promise<number> {
	const args = parsePlayArgs(argv.slice(2));
	const scenarios = findScenarios(root);
	const names = [...scenarios.keys()].sort();
	if (args.list) {
		for (const name of names) console.log(`${name}  (${relative(root, scenarios.get(name) ?? "")})`);
		return 0;
	}
	const file = scenarios.get(args.scenario);
	if (file === undefined) throw new Error(`no scenario ${args.scenario}; there are: ${names.join(", ")}`);
	const loaded: unknown = await import(pathToFileURL(file).href);
	const test: unknown = typeof loaded === "object" && loaded !== null ? Reflect.get(loaded, "default") : undefined;
	if (!(test instanceof Playtest)) throw new Error(`${file} must \`export default playtest({...}, async (t) => {...})\``);
	const godot = localGodot(root);
	if (!existsSync(godot)) throw new Error("Godot missing: run node tools/get-godot.ts");

	// The pid keeps two runs started in the same second apart: they match their games by log path.
	const stamp = `${new Date().toISOString().replaceAll(":", "-").slice(0, 19)}-${process.pid}`;
	const playDir = join(root, "build", "play");
	mkdirSync(playDir, { recursive: true });
	// Keeps Godot's importer away from the screenshots.
	writeFileSync(join(playDir, ".gdignore"), "");
	const outDir = join(playDir, args.scenario, stamp);
	const port = await freeUdpPort(args.port ?? preferredPort(Math.random()));
	const timeoutMs = (args.timeoutSeconds ?? DEFAULT_TIMEOUT_S) * 1000;
	const run = new PlayRun({ root, godot, outDir, port, headless: args.headless, timeoutMs, keep: args.keep, needs: test.meta.needs ?? [] });
	const started = new Date();
	console.log(`playtest ${args.scenario}: ${test.meta.title}\n  output: ${relative(root, outDir)}`);

	let base: Status = "passed";
	let error: string | undefined;
	let keeping = false;
	const write = (): Report => {
		const partial = {
			scenario: args.scenario,
			title: test.meta.title,
			started: started.toISOString(),
			durationMs: Date.now() - started.getTime(),
			headless: args.headless,
			port,
			steps: run.rec.steps,
			shots: run.rec.shots,
			logs: run.logs(test.meta.allowErrors ?? []),
			perf: run.perf(),
			...(error !== undefined ? { error } : {}),
		};
		const report: Report = { ...partial, status: finalStatus(partial, base) };
		writeFileSync(join(outDir, "report.json"), JSON.stringify(report, null, 2) + "\n");
		writeFileSync(join(outDir, "report.md"), reportMarkdown(report));
		writeFileSync(join(outDir, "review.md"), reviewMarkdown(report, outDir.replaceAll("\\", "/")));
		return report;
	};
	// Registered before any process starts, so it runs ahead of proc.ts's own Ctrl-C cleanup.
	const exitCode = (r: Report): number => (r.status === "passed" || r.status === "skipped" ? 0 : 1);
	for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"] as const) {
		process.once(signal, () => {
			// Under --keep the scenario is over and Ctrl-C is the expected way out.
			if (!keeping) {
				base = "interrupted";
				error ??= `stopped by ${signal}`;
			}
			run.killAll();
			const report = write();
			console.log(`\n${signal}: stopped; ${keeping ? `${report.status}, report` : "partial report"} in ${relative(root, outDir)}`);
			exit(keeping ? exitCode(report) : 130);
		});
	}

	let timer: NodeJS.Timeout | undefined;
	const deadline = new Promise<never>((_, reject) => {
		timer = setTimeout(() => {
			// Whatever the scenario is still waiting on fails from here on instead of driving on.
			run.rec.add("note", `timed out after ${timeoutMs / 1000} s`, false);
			run.rec.closed = true;
			reject(new Error(`timed out after ${timeoutMs / 1000} s`));
		}, timeoutMs);
	});
	try {
		await Promise.race([test.run(run.context()), deadline]);
	} catch (err) {
		if (err instanceof PlaytestSkip) {
			base = "skipped";
			error = err.message;
		} else {
			error = err instanceof Error ? err.message : String(err);
		}
	} finally {
		clearTimeout(timer);
	}
	if (args.keep && base !== "skipped" && run.running()) {
		keeping = true;
		write();
		console.log("\n--keep: the game keeps running; Ctrl-C ends it. The debug API (and the MCP server) reaches:");
		for (const line of run.describeProcesses()) console.log(`  ${line}`);
		await new Promise<never>(() => {});
	}
	await run.close();
	const report = write();
	console.log(`\n${report.status.toUpperCase()}${report.error !== undefined ? `: ${report.error}` : ""}`);
	for (const l of report.logs) for (const e of l.errors.slice(0, 5)) console.log(`  ${l.process}: ${e.trim()}`);
	if (report.shots.some((s) => s.file !== "")) console.log(`  screenshots for review: ${relative(root, join(outDir, "review.md"))}`);
	console.log(`  report: ${relative(root, join(outDir, "report.md"))}`);
	return exitCode(report);
}

try {
	exit(await main());
} catch (err) {
	console.error(err instanceof Error ? err.message : err);
	exit(1);
}

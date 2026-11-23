// What a playtest run (tools/play.ts) leaves behind: report.json for tools, report.md for
// people, and review.md, which holds only the screenshots and what each should show, for a
// reviewer who must not see the code or the state checks.

export type StepKind = "step" | "assert" | "wait" | "action" | "shot" | "note";

export interface StepRecord {
	// Milliseconds since the run started.
	at: number;
	kind: StepKind;
	title: string;
	ok: boolean;
	detail?: string;
}

export interface ImageCheck {
	title: string;
	ok: boolean;
	detail: string;
}

export interface ShotRecord {
	name: string;
	// Whose window it is.
	client: string;
	// Relative to the run folder; empty when none was taken (headless).
	file: string;
	expect: string;
	at: number;
	checks: ImageCheck[];
}

export interface LogRecord {
	process: string;
	file: string;
	errors: string[];
	allowed: number;
	warnings: string[];
	warningCount: number;
}

export interface PerfRecord {
	process: string;
	samples: number;
	minFps: number;
	maxP95Ms: number;
	maxFrameMs: number;
}

export type Status = "passed" | "failed" | "skipped" | "interrupted";

export interface Report {
	scenario: string;
	title: string;
	started: string;
	durationMs: number;
	status: Status;
	error?: string;
	headless: boolean;
	port: number;
	steps: StepRecord[];
	shots: ShotRecord[];
	logs: LogRecord[];
	perf: PerfRecord[];
}

// A run fails on a thrown error, a failed check, a failed image check or an error line in
// any process's log; skipped and interrupted stay what they are.
export function finalStatus(report: Omit<Report, "status">, base: Status): Status {
	if (base !== "passed") return base;
	if (report.error !== undefined) return "failed";
	if (report.steps.some((s) => !s.ok)) return "failed";
	if (report.shots.some((s) => s.checks.some((c) => !c.ok))) return "failed";
	if (report.logs.some((l) => l.errors.length > 0)) return "failed";
	return "passed";
}

const seconds = (ms: number): string => `${(ms / 1000).toFixed(1)} s`;

function cell(text: string): string {
	return text.replaceAll("|", "\\|").replaceAll(/\r?\n/g, " ");
}

export function reportMarkdown(r: Report): string {
	const out: string[] = [];
	out.push(`# Playtest: ${r.title}`, "");
	out.push(`Scenario \`${r.scenario}\`, started ${r.started}, took ${seconds(r.durationMs)}${r.headless ? ", headless (no screenshots)" : ""}, port ${r.port}.`, "");
	out.push(`**${r.status.toUpperCase()}**${r.error !== undefined ? `: ${r.error}` : ""}`, "");
	out.push("## Steps", "");
	out.push("| at | | what | detail |", "| --- | --- | --- | --- |");
	for (const s of r.steps) out.push(`| ${seconds(s.at)} | ${s.ok ? "ok" : "FAIL"} | ${s.kind}: ${cell(s.title)} | ${cell(s.detail ?? "")} |`);
	out.push("");
	if (r.shots.length > 0) {
		out.push("## Screenshots", "");
		for (const s of r.shots) {
			out.push(`- \`${s.file || "(not taken)"}\` (${s.client}, ${seconds(s.at)}): ${s.expect}`);
			for (const c of s.checks) out.push(`  - ${c.ok ? "ok" : "FAIL"} ${c.title}: ${c.detail}`);
		}
		out.push("");
	}
	out.push("## Logs", "");
	for (const l of r.logs) {
		out.push(`- ${l.process} (\`${l.file}\`): ${l.errors.length} error line(s)${l.allowed > 0 ? `, ${l.allowed} allowed` : ""}, ${l.warningCount} warning(s)`);
		for (const e of l.errors.slice(0, 10)) out.push(`  - \`${e.trim()}\``);
		for (const w of l.warnings.slice(0, 5)) out.push(`  - warning: \`${w.trim()}\``);
	}
	out.push("");
	if (r.perf.length > 0) {
		out.push("## Performance", "", "| process | samples | lowest fps | worst p95 frame | worst frame |", "| --- | --- | --- | --- | --- |");
		for (const p of r.perf) out.push(`| ${p.process} | ${p.samples} | ${p.minFps.toFixed(0)} | ${p.maxP95Ms.toFixed(1)} ms | ${p.maxFrameMs.toFixed(1)} ms |`);
		out.push("");
	}
	return out.join("\n");
}

// Only the pictures and what each should show: the reviewer judges what is on screen, not
// what the author meant or what the state checks said.
export function reviewMarkdown(r: Report, runDir: string): string {
	const shots = r.shots.filter((s) => s.file !== "");
	const out = [
		`# Screenshots to review: ${r.title}`,
		"",
		"Each image is one moment from a low-poly voxel 3D game (simple shapes and flat colours are intended). Judge each against its expectation alone.",
		"For each: (1) does it show what the expectation says, yes, partly or no, and why; (2) any blocking defect (missing or wrong element, black or broken rendering, things floating or clipping, unreadable text); (3) anything that looks unintentional. Name the image. Do not suggest code.",
		"",
	];
	for (const s of shots) out.push(`- ${runDir}/${s.file}`, `  Expectation: ${s.expect}`);
	if (shots.length === 0) out.push("(no screenshots in this run)");
	return out.join("\n") + "\n";
}

export interface PerfSample {
	fps: number;
	p95: number;
	max: number;
}

export function summarisePerf(process: string, samples: readonly PerfSample[]): PerfRecord {
	return {
		process,
		samples: samples.length,
		minFps: samples.length > 0 ? Math.min(...samples.map((s) => s.fps)) : 0,
		maxP95Ms: samples.length > 0 ? Math.max(...samples.map((s) => s.p95)) : 0,
		maxFrameMs: samples.length > 0 ? Math.max(...samples.map((s) => s.max)) : 0,
	};
}

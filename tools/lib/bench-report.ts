// The Markdown report `node tools/bench.ts all` writes to bench/report-<date>.md: one page
// with where each scenario's frame goes, what costs most, the worst hitches, the server's
// tick cost, what switching things off saves, and the change from this machine's baselines.
import { budgetLine, METRICS, passesLine, serverLine, type AblationDelta, type NetCost, type Regression, type ServerCost, type Spike, type Summary } from "./bench.ts";

export interface ScenarioResult {
	name: string;
	what: string;
	summary: Summary;
	baseline: Partial<Summary> | undefined;
	regressions: Regression[];
	// [zone or module, microseconds per frame], most expensive first.
	zones: [string, number][];
	modules: [string, number][];
	spikes: Spike[];
	net?: NetCost | undefined;
	// The server's own log: the solo server of a windowed run, or the dedicated server.
	server?: ServerCost | undefined;
}

export interface Failure {
	name: string;
	error: string;
}

export interface BenchReport {
	date: string;
	machine: string;
	commit: string;
	results: ScenarioResult[];
	failures: Failure[];
	ablation?: { scenario: string; full: Summary; deltas: AblationDelta[]; failures: Failure[] } | undefined;
}

const TOP_ZONES = 12;
const TOP_MODULES = 10;

// Text safe inside a Markdown table cell or list item: one line, no column breaks.
function cell(s: string): string {
	return s.replace(/\r?\n/g, " ").replaceAll("|", "\\|");
}

function gpu(s: Summary): string {
	if (s.gpu_ms !== null) return `${s.gpu_ms} (${s.driver || "?"})`;
	return s.driver === "" ? "n/a (headless)" : `untimed (${s.driver})`;
}

function signed(n: number): string {
	return n > 0 ? `+${n}` : String(n);
}

export function renderReport(r: BenchReport): string {
	const out: string[] = [
		`# Bench report ${r.date}`,
		"",
		`Machine: ${r.machine}. Commit: ${r.commit}. Timings are only comparable with runs on this machine; other work running at the same time shows up as noise.`,
		"",
		"## Frame budget",
		"",
		"Milliseconds per frame on the main thread: scripts (every moment a profile zone ran, nested zones once), physics (physics ticks outside zones, with the network receive Godot polls after the last tick), render (RenderingServer drawing, waiting on the GPU included), other (everything else: unzoned engine work such as animation, skeletons, particles, input, idle). GPU time runs alongside, so it is not part of the sum.",
		"",
		"| Scenario | Frame | p95 | Scripts | Physics | Render | Other | GPU | Samples |",
		"| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
	];
	for (const { name, summary: s } of r.results) {
		out.push(`| ${name} | ${s.frame_ms_mean} | ${s.frame_ms_p95} | ${s.budget_scripts_ms} | ${s.budget_physics_ms} | ${s.budget_render_ms} | ${s.budget_other_ms} | ${gpu(s)} | ${s.samples} |`);
	}
	for (const res of r.results) out.push("", ...scenario(res));
	if (r.ablation !== undefined) {
		const a = r.ablation;
		out.push(
			"",
			`## Ablation (${a.scenario})`,
			"",
			`Each row is ${a.scenario} again with one thing switched off, minus the full run (${budgetLine(a.full)}). Negative is what that thing costs.`,
			"",
			"| Off | Frame ms | Share | Scripts | Physics | Render | Other | GPU | Draw calls |",
			"| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
		);
		for (const d of a.deltas) {
			out.push(`| ${d.name} | ${signed(d.frame_ms)} | ${signed(Math.round(d.share * 100))}% | ${signed(d.scripts_ms)} | ${signed(d.physics_ms)} | ${signed(d.render_ms)} | ${signed(d.other_ms)} | ${d.gpu_ms === null ? "untimed" : signed(d.gpu_ms)} | ${signed(d.draw_calls)} |`);
		}
		for (const f of a.failures) out.push("", `- ${cell(f.name)}: ${cell(f.error)}`);
	}
	if (r.failures.length > 0) {
		out.push("", "## Failed", "");
		for (const f of r.failures) out.push(`- ${cell(f.name)}: ${cell(f.error)}`);
	}
	return out.join("\n") + "\n";
}

function scenario(res: ScenarioResult): string[] {
	const s = res.summary;
	const out = [`## ${res.name}`, "", cell(res.what), "", `- ${budgetLine(s)}`];
	if (s.driver !== "") out.push(`- ${passesLine(s)}`);
	out.push(`- nodes' physics ${s.physics_ms} ms a tick; ${s.draw_calls} draw calls, ${s.objects_drawn} objects, ${s.primitives} primitives in all; memory ${s.memory_mb} MB, ${s.nodes} nodes`);
	if (res.server !== undefined) out.push(`- Server${s.driver === "" ? "" : " (solo)"}: ${serverLine(res.server)}`);
	if (res.net !== undefined) out.push(`- Sent to each client: ${(res.net.outPerPeer / 1024).toFixed(1)} KB/s`);
	if (res.modules.length > 0) {
		out.push("", "Modules (microseconds per frame; nested zones in one module count twice):", "", "| Module | us/frame |", "| --- | --- |");
		for (const [m, us] of res.modules.slice(0, TOP_MODULES)) out.push(`| ${cell(m)} | ${us} |`);
	}
	if (res.zones.length > 0) {
		out.push("", "Top zones (microseconds per frame):", "", "| Zone | us/frame |", "| --- | --- |");
		for (const [z, us] of res.zones.slice(0, TOP_ZONES)) out.push(`| ${cell(z)} | ${us} |`);
	}
	if (res.spikes.length > 0) {
		out.push("", "Worst hitches:", "");
		for (const sp of res.spikes) {
			const ran = Object.entries(sp.zones).sort((a, b) => b[1] - a[1]).map(([z, ms]) => `${z} ${ms}`).join(", ");
			const compiles = Object.entries(sp.compiles).map(([k, c]) => `${c} ${k}`).join(", ");
			out.push(`- ${sp.ms} ms at ${sp.t} s: ${cell(ran || "no zones")}${compiles === "" ? "" : `; compiled ${compiles}`}`);
		}
	}
	out.push("");
	const base = res.baseline;
	if (base === undefined) {
		out.push("No baseline yet: this run was saved as one.");
		return out;
	}
	out.push("Against this machine's baseline:", "", "| Metric | Now | Baseline | Change |", "| --- | --- | --- | --- |");
	for (const m of METRICS) {
		const b = base[m];
		const now = s[m];
		if (typeof b !== "number") continue;
		const change = now === null || b === 0 ? "n/a" : `${now >= b ? "+" : ""}${(((now - b) / b) * 100).toFixed(1)}%`;
		out.push(`| ${m} | ${now ?? "untimed"} | ${b} | ${change} |`);
	}
	for (const reg of res.regressions) out.push("", `Regression: ${reg.metric} ${reg.baseline} -> ${reg.now}`);
	return out;
}

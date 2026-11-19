// Reads a report a tester sent (the game's "Report a bug", or the benchmark): unpacks it to a
// temp folder and prints the machine, where they were, how it ran, the worst hitches with
// what ran in each, and the last errors in the logs.
//   node tools/report.ts <slopocalypse-report-....zip>
import { existsSync, mkdtempSync, readdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { argv, exit } from "node:process";
import { worstSpikes } from "./lib/bench.ts";
import { extract } from "./lib/download.ts";
import { errorLines, printable, summariseReport } from "./lib/report.ts";

const TOP_SPIKES = 8;
const TOP_ERRORS = 10;

const zip = argv[2];
if (zip === undefined || !existsSync(zip)) {
	console.error("usage: node tools/report.ts <report.zip>");
	exit(1);
}
const dir = mkdtempSync(join(tmpdir(), "slopocalypse-report-"));
try {
	extract(zip, dir);
} catch {
	console.error(`${zip} could not be unpacked; is it a whole zip?`);
	exit(1);
}
const reportFile = join(dir, "report.json");
if (!existsSync(reportFile)) {
	console.error(`${zip} has no report.json; is it a Slopocalypse report?`);
	exit(1);
}
for (const line of summariseReport(JSON.parse(readFileSync(reportFile, "utf8")))) console.log(line);

const perfDir = join(dir, "perf");
for (const name of existsSync(perfDir) ? readdirSync(perfDir) : []) {
	// The whole session counts: a report is about what the tester saw, warm-up included.
	const spikes = worstSpikes(readFileSync(join(perfDir, name), "utf8"), 0, TOP_SPIKES);
	console.log(`\n${name}: ${spikes.length === 0 ? "no hitches logged" : "worst hitches (frame ms at second t: zones in ms, shader pipelines compiled)"}`);
	for (const s of spikes) {
		const ran = Object.entries(s.zones).sort((a, b) => b[1] - a[1]).map(([z, ms]) => `${z} ${ms}`).join(", ");
		const compiles = Object.entries(s.compiles).map(([k, c]) => `${c} ${k}`).join(", ");
		console.log(`  ${s.ms.toFixed(1).padStart(7)} ms at ${s.t.toFixed(1)} s: ${ran || "no zones"}${compiles === "" ? "" : `; compiled ${compiles}`}`);
	}
}

const logDir = join(dir, "logs");
for (const name of existsSync(logDir) ? readdirSync(logDir) : []) {
	const errors = errorLines(readFileSync(join(logDir, name), "utf8"), TOP_ERRORS);
	console.log(`\n${name}: ${errors.length === 0 ? "no errors" : `last ${errors.length} errors`}`);
	for (const e of errors) console.log(`  ${printable(e)}`);
}
console.log(`\nUnpacked in ${dir} (screenshot.png, logs/, perf/).`);

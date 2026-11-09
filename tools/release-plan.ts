// For the release workflow: asks changesetter what the next release is and writes the version,
// tag and release notes for later jobs.
//   node tools/release-plan.ts <notes file>
// Prints `version=`, `tag=` lines (append them to $GITHUB_OUTPUT); prints nothing when no
// pending changeset bumps the game.
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { argv, exit, platform } from "node:process";
import { changesetterBin } from "./lib/changesetter.ts";
import { parseReleasePlan, releaseNotes } from "./lib/release.ts";

const root = resolve(import.meta.dirname, "..");
const notesFile = argv[2];
if (notesFile === undefined) {
	console.error("usage: node tools/release-plan.ts <notes file>");
	exit(1);
}
const output = execFileSync(changesetterBin(root, platform), ["release", "--dry-run", "--output", "json"], { cwd: root, encoding: "utf8" });
const plan = parseReleasePlan(output);
if (plan !== undefined) {
	mkdirSync(dirname(resolve(notesFile)), { recursive: true });
	writeFileSync(notesFile, releaseNotes(plan));
	console.log(`version=${plan.version}`);
	console.log(`tag=${plan.tag}`);
}

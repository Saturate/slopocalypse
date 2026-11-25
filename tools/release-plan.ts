// For the release workflow: asks changesetter what the next release is and writes the version,
// tag and release notes for later jobs.
//   node tools/release-plan.ts <notes file>
// The RELEASE_NOTES environment variable, when set, goes at the top of the notes. The notes end
// with thanks to the authors of pull requests merged since the last release (needs `gh`).
// Prints `version=`, `tag=` lines (append them to $GITHUB_OUTPUT); prints nothing when no
// pending changeset bumps the game.
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { argv, env, exit, platform } from "node:process";
import { changesetterBin } from "./lib/changesetter.ts";
import { collectThanks } from "./lib/release-thanks.ts";
import { parseReleasePlan, releaseNotes } from "./lib/release.ts";

const root = resolve(import.meta.dirname, "..");
const notesFile = argv[2];
if (notesFile === undefined) {
	console.error("usage: node tools/release-plan.ts <notes file>");
	exit(1);
}
const output = execFileSync(changesetterBin(root, platform), ["release", "--dry-run", "--output", "json"], { cwd: root, encoding: "utf8" });
const plan = parseReleasePlan(output, (id) => {
	const file = join(root, ".changeset", `${id}.md`);
	return existsSync(file) ? readFileSync(file, "utf8") : undefined;
});
if (plan !== undefined) {
	mkdirSync(dirname(resolve(notesFile)), { recursive: true });
	writeFileSync(notesFile, releaseNotes(plan, true, { intro: env["RELEASE_NOTES"], thanks: collectThanks(root) }));
	console.log(`version=${plan.version}`);
	console.log(`tag=${plan.tag}`);
}

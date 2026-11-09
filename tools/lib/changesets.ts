// Gate step: a branch with changes must add a changeset, and every changeset must be valid.
// `changesetter check --base` only sees committed files, but the gate runs before the commit,
// so the gate works out "added on this branch" itself, untracked files included.
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { platform } from "node:process";
import { changesetterBin } from "./changesetter.ts";
import { run } from "./proc.ts";
import type { StepResult } from "./gate.ts";

const CHANGESET = /^\.changeset\/[^/]+\.md$/;

// The changeset files among the paths a branch adds (README.md in .changeset/ is not one).
export function addedChangesets(paths: readonly string[]): string[] {
	return paths.filter((p) => CHANGESET.test(p) && !p.endsWith("/README.md"));
}

function git(root: string, args: string[]): string[] {
	try {
		return execFileSync("git", args, { cwd: root, encoding: "utf8" }).split(/\r?\n/).filter(Boolean);
	} catch {
		return [];
	}
}

export async function checkChangesets(root: string): Promise<StepResult> {
	const bin = changesetterBin(root, platform);
	if (!existsSync(bin)) return { ok: false, detail: "changesetter not found. Run: node tools/get-changesetter.ts" };
	// Validates every pending changeset: frontmatter, package names, bump levels.
	const status = await run(bin, ["status"], { cwd: root, timeoutMs: 60_000 });
	if (status.code !== 0) return { ok: false, detail: status.output.trim() };
	const base = git(root, ["merge-base", "HEAD", "origin/main"])[0];
	if (base === undefined) return { ok: true, detail: "no origin/main to compare with; changesets valid" };
	const changed = [...git(root, ["diff", "--name-only", base]), ...git(root, ["ls-files", "--others", "--exclude-standard"])];
	if (changed.length === 0) return { ok: true, detail: "nothing changed since origin/main" };
	const added = addedChangesets([...git(root, ["diff", "--name-only", "--diff-filter=A", base]), ...git(root, ["ls-files", "--others", "--exclude-standard"])]);
	if (added.length > 0) return { ok: true, detail: `${added.length} changeset(s) on this branch` };
	return {
		ok: false,
		detail: [
			"this branch changes files but adds no changeset. Add one, written for players:",
			"  tools/changesetter/changesetter add --package slopocalypse --bump patch -m \"What changed, for players\"",
			"  (--bump none for tooling, docs and tests; minor for new features)",
		].join("\n"),
	};
}

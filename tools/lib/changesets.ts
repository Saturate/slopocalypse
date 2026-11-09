// Gate step: a branch with changes must add a changeset, and every changeset must be valid.
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { platform } from "node:process";
import { changesetterBin } from "./changesetter.ts";
import { run } from "./proc.ts";
import type { StepResult } from "./gate.ts";

const BASE = "origin/main";

function hasRef(root: string, ref: string): boolean {
	try {
		execFileSync("git", ["rev-parse", "--verify", "--quiet", ref], { cwd: root, stdio: "ignore" });
		return true;
	} catch {
		return false;
	}
}

export async function checkChangesets(root: string): Promise<StepResult> {
	const bin = changesetterBin(root, platform);
	if (!existsSync(bin)) return { ok: false, detail: "changesetter not found. Run: node tools/get-changesetter.ts" };
	// Validates every pending changeset: frontmatter, package names, bump levels.
	const status = await run(bin, ["status"], { cwd: root, timeoutMs: 60_000 });
	if (status.code !== 0) return { ok: false, detail: status.output.trim() };
	if (!hasRef(root, BASE)) return { ok: true, detail: `no ${BASE} to compare with; changesets valid` };
	// Counts committed, staged and untracked changesets added since the branch left the base,
	// and passes when nothing changed at all.
	const check = await run(bin, ["check", "--base", BASE], { cwd: root, timeoutMs: 60_000 });
	if (check.code === 0) return { ok: true, detail: check.output.trim().split(/\r?\n/)[0] ?? "changeset found" };
	return {
		ok: false,
		detail: [
			check.output.trim(),
			"This branch changes files but adds no changeset. Add one, written for players:",
			"  tools/changesetter/changesetter add --package slopocalypse --bump patch -m \"What changed, for players\"",
			"  (--bump none for tooling, docs and tests; minor for new features)",
		].join("\n"),
	};
}

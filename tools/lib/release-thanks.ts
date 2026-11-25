// Asks GitHub who to thank for a release: authors of pull requests merged since the previous
// release. Never throws; the notes are fine without the section.
import { execFileSync } from "node:child_process";
import { parsePullRequests, thanksLogins } from "./release.ts";

function gh(root: string, args: readonly string[]): string {
	return execFileSync("gh", args, { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
}

// The previous release's commit time, not its publish time: the release commit is made before
// the builds finish, so a PR merged while they ran is in neither release otherwise.
function previousReleaseTime(root: string): string | undefined {
	const latest = gh(root, ["api", "repos/{owner}/{repo}/releases/latest", "--jq", "[.tag_name, .published_at] | @tsv"]).split("\t");
	const [tag, published] = latest;
	let time = published;
	if (tag !== undefined && /^[\w.@-]+$/.test(tag)) {
		try {
			time = execFileSync("git", ["log", "-1", "--format=%cI", tag], { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
		} catch {
			// Tag not fetched locally: the publish time is the next best.
		}
	}
	const ms = time === undefined ? Number.NaN : Date.parse(time);
	return Number.isNaN(ms) ? undefined : new Date(ms).toISOString().replace(/\.\d+Z$/, "Z");
}

export function collectThanks(root: string): string[] {
	try {
		const since = previousReleaseTime(root);
		if (since === undefined) return [];
		const owner = gh(root, ["repo", "view", "--json", "owner", "--jq", ".owner.login"]);
		const prs = parsePullRequests(gh(root, ["pr", "list", "--state", "merged", "--search", `merged:>=${since}`, "--json", "author", "--limit", "500"]));
		return thanksLogins(prs, owner);
	} catch (err) {
		console.error(`warning: no thanks section, could not read merged pull requests: ${err instanceof Error ? err.message : String(err)}`);
		return [];
	}
}

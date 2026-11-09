// Pure parts of tools/release.ts: reading changesetter's plan, naming assets and image tags,
// and the release notes.

export const IMAGE = "ghcr.io/saturate/slopocalypse-server";
export const PACKAGE = "slopocalypse";

export interface ReleasePlan {
	version: string;
	tag: string;
	changelog: string;
}

function isRecord(v: unknown): v is Record<string, unknown> {
	return typeof v === "object" && v !== null && !Array.isArray(v);
}

// `changesetter release --dry-run --output json` prints a text summary, then the JSON.
// Returns undefined when nothing bumps the game's version.
export function parseReleasePlan(output: string): ReleasePlan | undefined {
	const start = output.indexOf("\n{");
	const json = output.startsWith("{") ? output : start >= 0 ? output.slice(start + 1) : "";
	if (json === "") throw new Error(`no JSON in changesetter output:\n${output}`);
	const parsed: unknown = JSON.parse(json);
	if (!isRecord(parsed) || !Array.isArray(parsed["releases"])) throw new Error("changesetter JSON has no releases list");
	for (const r of parsed["releases"]) {
		if (!isRecord(r) || r["name"] !== PACKAGE) continue;
		const { version, tag, changelog } = r;
		if (typeof version !== "string" || typeof tag !== "string") throw new Error("release entry without version or tag");
		return { version, tag, changelog: typeof changelog === "string" ? changelog : "" };
	}
	return undefined;
}

export function assetName(version: string, os: "windows" | "linux"): string {
	return `slopocalypse-${version}-${os}.zip`;
}

export function imageTags(version: string): string[] {
	return [`${IMAGE}:${version}`, `${IMAGE}:latest`];
}

// `gh auth status` lists "Token scopes: 'gist', 'repo', ...".
export function hasScope(authStatus: string, scope: string): boolean {
	const line = authStatus.split(/\r?\n/).find((l) => l.includes("Token scopes:"));
	return line !== undefined && line.includes(`'${scope}'`);
}

// Changeset bodies arrive as "#### Title" blocks; on a release page they read better as a list.
export function releaseNotes(plan: ReleasePlan): string {
	const items = plan.changelog
		.split(/\r?\n/)
		.map((l) => l.trim())
		.filter((l) => l.length > 0)
		.map((l) => "- " + l.replace(/^#+\s*/, "").replace(/^-\s*/, ""));
	return [
		"## What changed",
		"",
		...(items.length > 0 ? items : ["- Small fixes."]),
		"",
		"## Get it",
		"",
		`- Windows: download \`${assetName(plan.version, "windows")}\`, unzip, run \`Slopocalypse.exe\`.`,
		`- Linux: download \`${assetName(plan.version, "linux")}\`, unzip, run \`Slopocalypse.x86_64\`.`,
		`- Server: \`docker run -d -p 7777:7777/udp -v slopocalypse-data:/data ${IMAGE}:${plan.version}\``,
		"",
	].join("\n");
}

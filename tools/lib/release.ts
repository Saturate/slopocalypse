// Pure parts of tools/release.ts: reading changesetter's plan, naming assets and image tags,
// and the release notes.

export const IMAGE = "ghcr.io/saturate/slopocalypse-server";
export const PACKAGE = "slopocalypse";

export type Bump = "major" | "minor" | "patch" | "none";

export interface Entry {
	bump: Bump;
	text: string;
}

export interface ReleasePlan {
	version: string;
	tag: string;
	changelog: string;
	// Each change with its bump, for grouping the notes; empty when the files were unreadable.
	entries: Entry[];
	// Changes players never see (`none`).
	internal: string[];
}

function isRecord(v: unknown): v is Record<string, unknown> {
	return typeof v === "object" && v !== null && !Array.isArray(v);
}

// One line of text per change: changeset bodies come as "#### Title" or plain text.
function clean(text: string): string {
	return text
		.split(/\r?\n/)
		.map((l) => l.trim().replace(/^#+\s*/, "").replace(/^-\s*/, ""))
		.filter((l) => l.length > 0)
		.join(" ");
}

// A changeset file: front matter `package: bump`, then the summary.
export function parseChangeset(text: string, pkg: string = PACKAGE): Entry | undefined {
	const m = /^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/.exec(text);
	if (m === null) return undefined;
	const line = m[1]!.split(/\r?\n/).find((l) => l.trim().replace(/^["']|["']$/g, "").startsWith(pkg));
	const bump = line?.split(":")[1]?.trim().replace(/^["']|["']$/g, "");
	if (bump !== "major" && bump !== "minor" && bump !== "patch" && bump !== "none") return undefined;
	return { bump, text: clean(m[2]!) };
}

// `changesetter release --dry-run --output json` prints a text summary, then the JSON.
// `readChangeset(id)` returns a changeset file's text (before the release consumes it).
// Returns undefined when nothing bumps the game's version.
export function parseReleasePlan(output: string, readChangeset: (id: string) => string | undefined = () => undefined): ReleasePlan | undefined {
	const start = output.indexOf("\n{");
	const json = output.startsWith("{") ? output : start >= 0 ? output.slice(start + 1) : "";
	if (json === "") throw new Error(`no JSON in changesetter output:\n${output}`);
	const parsed: unknown = JSON.parse(json);
	if (!isRecord(parsed) || !Array.isArray(parsed["releases"])) throw new Error("changesetter JSON has no releases list");
	const internal = Array.isArray(parsed["none_entries"])
		? parsed["none_entries"].flatMap((e) => (isRecord(e) && typeof e["title"] === "string" ? [clean(e["title"])] : []))
		: [];
	for (const r of parsed["releases"]) {
		if (!isRecord(r) || r["name"] !== PACKAGE) continue;
		const { version, tag, changelog, changesets } = r;
		if (typeof version !== "string" || typeof tag !== "string") throw new Error("release entry without version or tag");
		const entries: Entry[] = [];
		for (const id of Array.isArray(changesets) ? changesets : []) {
			const text = typeof id === "string" ? readChangeset(id) : undefined;
			const entry = text === undefined ? undefined : parseChangeset(text);
			if (entry !== undefined && entry.bump !== "none") entries.push(entry);
		}
		return { version, tag, changelog: typeof changelog === "string" ? changelog : "", entries, internal };
	}
	return undefined;
}

export function assetName(version: string, os: "windows" | "linux" | "macos"): string {
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

const SECTIONS: readonly [Bump, string][] = [
	["major", "Breaking changes"],
	["minor", "Features"],
	["patch", "Fixes and improvements"],
];

// Grouped by kind of change when the changesets were readable, one list otherwise.
// `mac`: whether this release ships a macOS zip (the workflow builds one; the local fallback
// on Windows cannot).
export function releaseNotes(plan: ReleasePlan, mac = true): string {
	const out: string[] = [];
	if (plan.entries.length > 0) {
		for (const [bump, title] of SECTIONS) {
			const items = plan.entries.filter((e) => e.bump === bump).map((e) => `- ${e.text}`);
			if (items.length > 0) out.push(`## ${title}`, "", ...items, "");
		}
	} else {
		const items = plan.changelog.split(/\r?\n/).map(clean).filter((l) => l.length > 0).map((l) => `- ${l}`);
		out.push("## What changed", "", ...(items.length > 0 ? items : ["- Small fixes."]), "");
	}
	if (plan.internal.length > 0) out.push("## Under the hood", "", ...plan.internal.map((t) => `- ${t}`), "");
	out.push(
		"## Get it",
		"",
		`- Windows: download \`${assetName(plan.version, "windows")}\`, unzip, run \`Slopocalypse.exe\`.`,
		`- Linux: download \`${assetName(plan.version, "linux")}\`, unzip, run \`Slopocalypse.x86_64\`.`,
		...(mac ? [`- macOS (Apple silicon and Intel): download \`${assetName(plan.version, "macos")}\`, unzip, right-click \`Slopocalypse.app\` > Open the first time (it is not notarised).`] : []),
		`- Server: \`docker run -d -p 7777:7777/udp -v slopocalypse-data:/data ${IMAGE}:${plan.version}\``,
		"",
	);
	return out.join("\n");
}

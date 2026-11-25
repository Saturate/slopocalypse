import assert from "node:assert/strict";
import { test } from "node:test";
import { assetName, hasScope, imageTags, parseChangeset, parsePullRequests, parseReleasePlan, releaseNotes, thanksLogins } from "./release.ts";

const DRY_RUN = `Dry run - the following changes would be made:

  slopocalypse 0.0.0 -> 0.1.0 (minor)

Changelog date: 2026-11-09
{
  "releases": [
    { "name": "slopocalypse", "version": "0.1.0", "previous_version": "0.0.0", "bump": "minor", "tag": "v0.1.0",
      "changelog": "#### Servers can run from a Docker image.\\n\\n#### Trees fall where you shoot them.", "changesets": ["a", "b"] }
  ],
  "none_entries": []
}`;

test("the plan comes from the JSON after changesetter's text summary", () => {
	assert.deepEqual(parseReleasePlan(DRY_RUN), {
		version: "0.1.0",
		tag: "v0.1.0",
		changelog: "#### Servers can run from a Docker image.\n\n#### Trees fall where you shoot them.",
		entries: [],
		internal: [],
	});
});

test("a changeset file gives its bump and one line of summary", () => {
	assert.deepEqual(parseChangeset("---\nslopocalypse: minor\n---\n\n#### Press F3 for numbers.\n"), { bump: "minor", text: "Press F3 for numbers." });
	assert.deepEqual(parseChangeset('---\n"slopocalypse": patch\n---\n\nFixed a crash.\n'), { bump: "patch", text: "Fixed a crash." });
	assert.equal(parseChangeset("no front matter"), undefined);
});

test("the plan reads each changeset's bump, and lists the internal ones", () => {
	const files: Record<string, string> = {
		a: "---\nslopocalypse: minor\n---\n\nServers can run from a Docker image.\n",
		b: "---\nslopocalypse: patch\n---\n\nTrees fall where you shoot them.\n",
	};
	const withInternal = DRY_RUN.replace('"none_entries": []', '"none_entries": [{ "title": "#### Benchmarks exist.", "body": "x" }]');
	const plan = parseReleasePlan(withInternal, (id) => files[id]);
	assert.deepEqual(plan?.entries, [
		{ bump: "minor", text: "Servers can run from a Docker image." },
		{ bump: "patch", text: "Trees fall where you shoot them." },
	]);
	assert.deepEqual(plan?.internal, ["Benchmarks exist."]);
});

test("only none changesets pending means there is nothing to release", () => {
	assert.equal(parseReleasePlan('{ "releases": [], "none_entries": [{ "title": "x", "body": "x" }] }'), undefined);
});

test("output without JSON is an error, not an empty release", () => {
	assert.throws(() => parseReleasePlan("error: something broke"), /no JSON/);
});

test("assets and image tags carry the version", () => {
	assert.equal(assetName("0.1.0", "windows"), "slopocalypse-0.1.0-windows.zip");
	assert.deepEqual(imageTags("0.1.0"), ["ghcr.io/saturate/slopocalypse-server:0.1.0", "ghcr.io/saturate/slopocalypse-server:latest"]);
});

test("the package scope is read from gh auth status", () => {
	const status = "  - Token scopes: 'gist', 'read:org', 'repo', 'workflow'";
	assert.equal(hasScope(status, "repo"), true);
	assert.equal(hasScope(status, "write:packages"), false);
	assert.equal(hasScope(status + ", 'write:packages'", "write:packages"), true);
});

test("release notes group features, fixes and under the hood", () => {
	const notes = releaseNotes({
		version: "0.2.0",
		tag: "v0.2.0",
		changelog: "",
		entries: [
			{ bump: "patch", text: "Fixed a crash." },
			{ bump: "minor", text: "Press F3 for numbers." },
		],
		internal: ["Benchmarks exist."],
	});
	const features = notes.indexOf("## Features");
	const fixes = notes.indexOf("## Fixes and improvements");
	const hood = notes.indexOf("## Under the hood");
	assert.ok(features >= 0 && features < fixes && fixes < hood);
	const f3 = notes.indexOf("- Press F3 for numbers.");
	const crash = notes.indexOf("- Fixed a crash.");
	assert.ok(f3 > features && f3 < fixes);
	assert.ok(crash > fixes && crash < hood);
	assert.equal(notes.includes("## Breaking changes"), false);
});

test("without readable changesets the notes list the changelog, and say how to get the build", () => {
	const notes = releaseNotes({ version: "0.1.0", tag: "v0.1.0", changelog: "#### Servers can run from a Docker image.\n\n#### Trees fall.", entries: [], internal: [] });
	assert.match(notes, /^- Servers can run from a Docker image\.$/m);
	assert.match(notes, /^- Trees fall\.$/m);
	assert.match(notes, /slopocalypse-0\.1\.0-windows\.zip/);
	assert.match(notes, /slopocalypse-server:0\.1\.0/);
});

test("the notes list the macOS zip only when the release ships one", () => {
	const plan = { version: "0.4.0", tag: "v0.4.0", changelog: "", entries: [{ bump: "minor" as const, text: "Macs." }], internal: [] };
	assert.match(releaseNotes(plan), /slopocalypse-0\.4\.0-macos\.zip/);
	assert.doesNotMatch(releaseNotes(plan, false), /macos/);
});

test("the releaser's text goes at the top, above the changes", () => {
	const plan = { version: "0.4.0", tag: "v0.4.0", changelog: "", entries: [{ bump: "minor" as const, text: "Macs." }], internal: [] };
	const notes = releaseNotes(plan, true, { intro: "  A big one.\n\nHave fun.  " });
	assert.ok(notes.startsWith("A big one.\n\nHave fun.\n\n## Features"));
	assert.ok(releaseNotes(plan, true, { intro: "   " }).startsWith("## Features"));
	assert.ok(releaseNotes(plan).startsWith("## Features"));
});

test("the thanks come last and are left out when nobody is named", () => {
	const plan = { version: "0.4.0", tag: "v0.4.0", changelog: "", entries: [{ bump: "minor" as const, text: "Macs." }], internal: [] };
	const notes = releaseNotes(plan, true, { thanks: ["a", "b", "c"] });
	assert.ok(notes.trimEnd().endsWith("## Thanks\n\nThanks to @a, @b and @c for their work in this release."));
	assert.match(releaseNotes(plan, true, { thanks: ["a"] }), /Thanks to @a for their work/);
	assert.match(releaseNotes(plan, true, { thanks: ["a", "b"] }), /Thanks to @a and @b for/);
	assert.doesNotMatch(releaseNotes(plan, true, { thanks: [] }), /Thanks/);
});

test("thanks name PR authors once, without bots and the repo owner", () => {
	const prs = [
		{ author: { login: "Saturate", is_bot: false } },
		{ author: { login: "zed", is_bot: false } },
		{ author: { login: "dependabot[bot]", is_bot: false } },
		{ author: { login: "app/github-actions", is_bot: true } },
		{ author: { login: "Amy", is_bot: false } },
		{ author: { login: "zed", is_bot: false } },
		{ author: { login: "amy", is_bot: false } },
		{ author: { login: "bad login", is_bot: false } },
		{ author: null },
	];
	assert.deepEqual(thanksLogins(prs, "saturate"), ["Amy", "zed"]);
});

test("the PR list from gh is read without trusting its shape", () => {
	const json = JSON.stringify([{ number: 1, author: { login: "a", is_bot: false } }, { number: 2, author: { login: "b", is_bot: true } }, { number: 3 }, "x"]);
	assert.deepEqual(parsePullRequests(json), [{ author: { login: "a", is_bot: false } }, { author: { login: "b", is_bot: true } }, { author: null }]);
	assert.throws(() => parsePullRequests("{}"));
});

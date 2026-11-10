import assert from "node:assert/strict";
import { test } from "node:test";
import { assetName, hasScope, imageTags, parseChangeset, parseReleasePlan, releaseNotes } from "./release.ts";

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

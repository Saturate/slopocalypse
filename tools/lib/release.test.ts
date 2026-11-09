import assert from "node:assert/strict";
import { test } from "node:test";
import { assetName, hasScope, imageTags, parseReleasePlan, releaseNotes } from "./release.ts";

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
	});
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

test("release notes list each change and how to get the build", () => {
	const notes = releaseNotes({ version: "0.1.0", tag: "v0.1.0", changelog: "#### Servers can run from a Docker image.\n\n#### Trees fall." });
	assert.match(notes, /^- Servers can run from a Docker image\.$/m);
	assert.match(notes, /^- Trees fall\.$/m);
	assert.match(notes, /slopocalypse-0\.1\.0-windows\.zip/);
	assert.match(notes, /slopocalypse-server:0\.1\.0/);
});

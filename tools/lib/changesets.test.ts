import assert from "node:assert/strict";
import { test } from "node:test";
import { addedChangesets } from "./changesets.ts";

test("only markdown files directly in .changeset count as changesets", () => {
	assert.deepEqual(
		addedChangesets([".changeset/bold-ants-bolt.md", ".changeset/README.md", ".changeset/pre.json", "docs/.changeset/x.md", "core/boot.gd"]),
		[".changeset/bold-ants-bolt.md"],
	);
});

test("a branch with no changeset files has none", () => {
	assert.deepEqual(addedChangesets(["core/boot.gd", "README.md"]), []);
});

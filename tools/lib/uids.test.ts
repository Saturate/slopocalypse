import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..", "..");

// Godot writes a .uid beside every script on import. One that isn't committed appears on
// CI's fresh checkout as a new file, and on main the changesets step then fails: files
// changed, no changeset.
test("every committed script has its .uid committed", () => {
	const files = new Set(execFileSync("git", ["ls-files"], { cwd: root, encoding: "utf8" }).split("\n"));
	const missing = [...files].filter((f) => f.endsWith(".gd") && !f.startsWith("addons/") && !files.has(`${f}.uid`));
	assert.deepEqual(missing, [], `commit the .uid files: ${missing.join(", ")}`);
});

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { expectedSha512, verifySha512 } from "./checksum.ts";

const sumsFor = (entries: Record<string, string>): string =>
	Object.entries(entries)
		.map(([name, hash]) => `${hash}  ${name}`)
		.join("\n");

test("finds the hash for an exact file name, not a prefix match", () => {
	const sums = sumsFor({ "a.zip.sig": "1".repeat(128), "a.zip": "2".repeat(128) });
	assert.equal(expectedSha512(sums, "a.zip"), "2".repeat(128));
});

test("throws when the file is missing from the sums list", () => {
	assert.throws(() => expectedSha512(sumsFor({ "b.zip": "3".repeat(128) }), "a.zip"), /not listed/);
});

test("accepts a file whose hash matches and rejects one that does not", async () => {
	const dir = mkdtempSync(join(tmpdir(), "outpost-sum-"));
	const file = join(dir, "fake.zip");
	writeFileSync(file, "fake archive bytes");
	const good = createHash("sha512").update("fake archive bytes").digest("hex");

	await verifySha512(file, good);
	await assert.rejects(verifySha512(file, "0".repeat(128)), /checksum mismatch/);
});

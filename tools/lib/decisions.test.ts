import assert from "node:assert/strict";
import { readdirSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

// Two branches in flight once both took 0019; a number is how other files point at a record.
test("every decision record has its own number", () => {
	const dir = join(import.meta.dirname, "..", "..", "docs", "decisions");
	const seen = new Map<string, string>();
	const clashes: string[] = [];
	for (const name of readdirSync(dir)) {
		const number = /^(\d{4})-/.exec(name)?.[1];
		if (number === undefined) continue;
		const other = seen.get(number);
		if (other !== undefined) clashes.push(`${other} and ${name}`);
		else seen.set(number, name);
	}
	assert.deepEqual(clashes, []);
});

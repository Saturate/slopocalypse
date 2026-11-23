import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import { ownershipProblems, parseClaims, repoOwnershipProblems } from "./ownership.ts";

const modules = [
	parseClaims("glowsticks", { debug_calls: ["lit_of"], settings: [] }),
	parseClaims("compass", { settings: [{ key: "compass", type: "bool" }] }),
];

function problems(files: Record<string, string>): string[] {
	return ownershipProblems(Object.keys(files), (f) => files[f] ?? "", modules);
}

test("claims come from the manifest, missing fields are empty", () => {
	assert.deepEqual(parseClaims("x", { debug_calls: ["a", 1], settings: [{ key: "k" }, "junk"] }), { id: "x", debugCalls: ["a"], settings: ["k"] });
	assert.deepEqual(parseClaims("y", null), { id: "y", debugCalls: [], settings: [] });
});

test("a scenario outside its module's playtests folder fails", () => {
	const scenario = 'import { playtest } from "../lib/play.ts";\nexport default playtest({ title: "x" }, async () => {});\n';
	assert.equal(problems({ "tools/playtests/night.ts": scenario }).length, 1);
	assert.deepEqual(problems({ "modules/glowsticks/playtests/night.ts": scenario }), []);
	// Mentioning the shape in a message is not a scenario.
	assert.deepEqual(problems({ "tools/play.ts": "throw new Error(`must \\`export default playtest(...)\\``);" }), []);
});

test("a debug call named outside its module fails, inside it is fine", () => {
	assert.match(problems({ "modules/debug_api/scripts/debug_handler.gd": 'const CALLS := ["glowsticks:lit_of"]' })[0] ?? "", /glowsticks:lit_of/);
	assert.deepEqual(problems({ "modules/glowsticks/tests/unit/test_x.gd": 'var t := "glowsticks:lit_of"' }), []);
	// Only declared calls: an EventBus topic naming the module is how modules talk.
	assert.deepEqual(problems({ "core/x.gd": 'EventBus.publish(&"glowsticks.lit", {})' }), []);
});

test("a module's setting key in core fails; the module itself and other modules may read it", () => {
	assert.match(problems({ "core/ui/settings_screen.gd": '_toggle("Compass", "compass")' })[0] ?? "", /setting "compass"/);
	assert.deepEqual(problems({ "modules/compass/scripts/strip.gd": 'Settings.value("compass")' }), []);
	assert.deepEqual(problems({ "core/x.gd": 'Features.is_enabled(&"compass_strip")' }), []);
});

test("the repository follows the rule", () => {
	assert.deepEqual(repoOwnershipProblems(join(import.meta.dirname, "..", "..")), []);
});

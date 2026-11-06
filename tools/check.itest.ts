// Proves the gate fails on each failure class it exists to catch. Slow (starts Godot),
// so it runs only in `check --full`.
import { test, after } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { checkScripts, runGdUnit } from "./lib/gate.ts";
import { localGodot } from "./lib/godot.ts";

const root = resolve(import.meta.dirname, "..");
const godot = localGodot(root);
// Fixtures must sit inside the project so res:// paths resolve; the leading dot keeps
// findTestDirs and git from picking them up.
const fixtures = mkdtempSync(join(root, ".selftest-"));
after(() => rmSync(fixtures, { recursive: true, force: true }));

function suite(name: string, body: string): string {
	const dir = join(fixtures, name);
	mkdirSync(dir, { recursive: true });
	writeFileSync(join(dir, `test_${name}.gd`), `extends GdUnitTestSuite\n\n${body}\n`);
	return dir;
}

test("passing suite passes", async () => {
	const r = await runGdUnit(godot, root, [suite("pass", "func test_ok() -> void:\n\tassert_bool(true).is_true()")]);
	assert.equal(r.ok, true, r.detail);
});

test("failing assertion fails the gate", async () => {
	const r = await runGdUnit(godot, root, [suite("fail", "func test_bad() -> void:\n\tassert_int(1).is_equal(2)")]);
	assert.equal(r.ok, false);
});

test("parse error fails the gate", async () => {
	const r = await runGdUnit(godot, root, [suite("parse", "func test_parse() -> void:\n\tvar x: int =")]);
	assert.equal(r.ok, false);
});

test("runtime SCRIPT ERROR fails the gate", async () => {
	const body = 'func test_rt() -> void:\n\tvar d: Dictionary = {}\n\tvar v: int = d["missing"]\n\tassert_bool(true).is_true()';
	const r = await runGdUnit(godot, root, [suite("runtime", body)]);
	assert.equal(r.ok, false);
});

test("push_error fails the gate even though gdUnit4 passes the test", async () => {
	const body = 'func test_push() -> void:\n\tpush_error("silent failure")\n\tassert_bool(true).is_true()';
	const r = await runGdUnit(godot, root, [suite("push", body)]);
	assert.equal(r.ok, false);
	assert.match(r.detail, /silent failure/);
});

test("type error in a script fails the parse check", async () => {
	const file = join(fixtures, "bad_type.gd");
	writeFileSync(file, 'extends Node\n\nfunc f() -> int:\n\tvar x: int = "str"\n\treturn x\n');
	const r = await checkScripts(godot, root, [file]);
	assert.equal(r.ok, false);
});

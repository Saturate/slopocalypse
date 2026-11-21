import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { guessSeconds, listSuites, planShards, retryOnce, shardCount, suiteTimes, userDirEnv, type StepResult } from "./gate.ts";

test("a step that passes runs once", async () => {
	let runs = 0;
	const r = await retryOnce(async (): Promise<StepResult> => {
		runs++;
		return { ok: true, detail: "clean" };
	});
	assert.equal(runs, 1);
	assert.deepEqual(r, { ok: true, detail: "clean" });
});

test("a step that fails once and then passes passes, and says it was retried", async () => {
	let runs = 0;
	const r = await retryOnce(async (): Promise<StepResult> => {
		runs++;
		return runs === 1 ? { ok: false, detail: "import exit -1" } : { ok: true, detail: "clean" };
	});
	assert.equal(runs, 2);
	assert.equal(r.ok, true);
	assert.match(r.detail, /retried/);
	assert.match(r.detail, /import exit -1/);
});

test("a step that fails twice fails with the second result", async () => {
	let runs = 0;
	const r = await retryOnce(async (): Promise<StepResult> => {
		runs++;
		return { ok: false, detail: `failure ${runs}` };
	});
	assert.equal(runs, 2);
	assert.deepEqual(r, { ok: false, detail: "failure 2" });
});

test("shards come out close to even, the longest suites spread first", () => {
	const suites = [
		{ path: "a", seconds: 90 },
		{ path: "b", seconds: 60 },
		{ path: "c", seconds: 40 },
		{ path: "d", seconds: 30 },
		{ path: "e", seconds: 20 },
		{ path: "f", seconds: 10 },
	];
	const shards = planShards(suites, 3);
	const total = (paths: string[]): number => paths.reduce((sum, p) => sum + (suites.find((s) => s.path === p)?.seconds ?? 0), 0);
	assert.deepEqual(shards.map(total), [90, 80, 80]);
	assert.deepEqual(shards.flat().sort(), ["a", "b", "c", "d", "e", "f"]);
});

test("no empty shards when there are fewer suites than processes", () => {
	assert.deepEqual(planShards([{ path: "a", seconds: 1 }], 4), [["a"]]);
	assert.equal(shardCount(16, 3), 3);
	assert.equal(shardCount(1, 50), 1);
	assert.ok(shardCount(64, 500) <= 6);
});

test("a suite without a recorded time gets a guess by kind", () => {
	const known = { "res://m/tests/scenario/test_known.gd": 42 };
	assert.equal(guessSeconds("res://m/tests/scenario/test_known.gd", known), 42);
	assert.ok(guessSeconds("res://m/tests/scenario/test_new.gd", known) > guessSeconds("res://m/tests/unit/test_new.gd", known));
});

test("reads suite times from a gdUnit report", () => {
	const xml = [
		'<testsuites id="x" name="report_3" tests="2" failures="0" time="0.000">',
		'\t<testsuite id="0" name="test_fights" package="modules/enemies/tests/scenario" timestamp="t" hostname="localhost" tests="2" failures="0" errors="0" skipped="0" flaky="0" time="95.5">',
		'\t\t<testcase name="test_one" classname="test_fights" time="90.0">',
	].join("\n");
	assert.deepEqual(suiteTimes(xml), { "res://modules/enemies/tests/scenario/test_fights.gd": 95.5 });
});

test("each OS moves Godot's user folder with its own variable", () => {
	assert.deepEqual(userDirEnv("linux", "/tmp/a"), { XDG_DATA_HOME: "/tmp/a" });
	assert.deepEqual(userDirEnv("darwin", "/tmp/a"), { HOME: "/tmp/a" });
	assert.deepEqual(userDirEnv("win32", "C:/t/a"), { APPDATA: "C:/t/a" });
});

test("finds test_*.gd suites only, in a stable order", () => {
	const dir = mkdtempSync(join(tmpdir(), "gate-suites-"));
	try {
		mkdirSync(join(dir, "unit"));
		mkdirSync(join(dir, "scenario"));
		for (const f of ["unit/test_b.gd", "unit/helper.gd", "scenario/test_a.gd", "scenario/test_a.gd.uid"]) writeFileSync(join(dir, f), "");
		assert.deepEqual(listSuites([dir]), [join(dir, "scenario", "test_a.gd"), join(dir, "unit", "test_b.gd")]);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});

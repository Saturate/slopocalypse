import { test } from "node:test";
import assert from "node:assert/strict";
import { errorDetails, failureLines, scanLog, stripAnsi, testSummary } from "./log-scan.ts";

const NOISE = [/Remote Debugger: Unable to connect to host '127\.0\.0\.1:0'/, /remote port number must be between/];

test("clean log has no problems", () => {
	assert.deepEqual(scanLog("Godot Engine v4.7.2\nall good\n", NOISE), []);
});

test("flags SCRIPT ERROR, ERROR: and mixed-case Error: lines", () => {
	const log = [
		"SCRIPT ERROR: Invalid access to property",
		"ERROR: something bad",
		"Error: Can't run project: no main scene defined in the project.",
	].join("\n");
	assert.equal(scanLog(log, NOISE).length, 3);
});

test("ignores allow-listed noise", () => {
	const log = [
		"ERROR: The remote port number must be between 1 and 65535 (inclusive).",
		"ERROR: Remote Debugger: Unable to connect to host '127.0.0.1:0'.",
	].join("\n");
	assert.deepEqual(scanLog(log, NOISE), []);
});

test("does not flag words like 'errors' in summaries", () => {
	assert.deepEqual(scanLog("Statistics: 1 test cases | 0 errors | 0 failures", NOISE), []);
});

test("strips ANSI colour codes before matching", () => {
	assert.equal(stripAnsi("\u001b[38;2;220;20;60mFAILED\u001b[0m"), "FAILED");
	assert.equal(scanLog("\u001b[31mERROR: boom\u001b[0m", NOISE).length, 1);
});

test("reads the gdUnit overall summary, and reports a missing one as undefined", () => {
	const log = "Overall Summary: 3 test cases | 1 errors | 2 failures | 0 flaky | 0 skipped | 0 orphans |";
	assert.deepEqual(testSummary(log), { cases: 3, errors: 1, failures: 2 });
	assert.equal(testSummary("crashed before summary"), undefined);
});

test("errorDetails keeps the lines Godot prints under an error, up to its at: line", () => {
	const log = [
		"Loading resource: res://a.tres",
		'ERROR: Cannot export project with preset "macOS" due to configuration errors:',
		"Cannot export for universal or arm64 if ETC2 ASTC texture format is disabled.",
		"",
		"   at: _fs_changed (editor/editor_node.cpp:1401)",
		"Class 'X' is not exposed, skipping.",
		"ERROR: The remote port number must be between 1 and 65535 (inclusive).",
		"   at: somewhere",
	].join("\n");
	assert.deepEqual(errorDetails(log, NOISE), [
		'ERROR: Cannot export project with preset "macOS" due to configuration errors:\nCannot export for universal or arm64 if ETC2 ASTC texture format is disabled.',
	]);
});

// Captured from gdUnit4 (colours included): an is_equal failure, then an is_equal_approx one.
const GDUNIT_FAILURES = [
	"\u001b[38;2;250;235;215mres://tests/unit/test_a.gd\u001b[0m > test_eq\u001b[38;2;178;34;34m FAILED\u001b[0m 1ms",
	"  Report:",
	"  \u001b[38;2;255;69;0mExpecting:\u001b[0m",
	" '4'",
	" but was",
	" '3'\tat 'test_eq' in res://tests/unit/test_a.gd:5",
	"",
	"  res://tests/unit/test_b.gd > test_near FAILED 1ms",
	"  Report:",
	"  Expecting:",
	" 100.000000",
	" in range between",
	" 84.999000 <> 85.001000\tat 'test_near' in res://tests/unit/test_b.gd:3",
	"",
	"Statistics: 2 test cases | 0 errors | 2 failures | 0 flaky | 0 skipped | 0 orphans | FAILED 5ms",
].join("\n");

test("failure lines keep both the expected and the actual value", () => {
	const lines = failureLines(GDUNIT_FAILURES);
	assert.deepEqual(lines.map((l) => l.trim()), [
		"res://tests/unit/test_a.gd > test_eq FAILED 1ms",
		"Expecting:",
		"'4'",
		"but was",
		"'3'\tat 'test_eq' in res://tests/unit/test_a.gd:5",
		"res://tests/unit/test_b.gd > test_near FAILED 1ms",
		"Expecting:",
		"100.000000",
		"in range between",
		"84.999000 <> 85.001000\tat 'test_near' in res://tests/unit/test_b.gd:3",
	]);
});

test("failure lines have room for several failures", () => {
	const many = Array.from({ length: 12 }, () => GDUNIT_FAILURES).join("\n");
	assert.equal(failureLines(many).length, 60);
});

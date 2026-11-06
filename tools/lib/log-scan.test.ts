import { test } from "node:test";
import assert from "node:assert/strict";
import { scanLog, stripAnsi, testSummary } from "./log-scan.ts";

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

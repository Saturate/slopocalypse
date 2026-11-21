import assert from "node:assert/strict";
import { platform } from "node:process";
import { test } from "node:test";
import { run } from "./proc.ts";

// Process groups are POSIX; Windows goes through taskkill and is covered by the gate runs there.
const posix = { skip: platform === "win32" };

function alive(pid: number): boolean {
	try {
		process.kill(pid, 0);
		return true;
	} catch {
		return false;
	}
}

const delay = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

// `sh` starts a child that outlives nothing on its own, prints its pid, and holds the output open.
const HOLDER = "sleep 60 & echo child=$!; wait";

const childPid = (output: string): number => Number(/child=(\d+)/.exec(output)?.[1] ?? NaN);

test("a timeout ends the command and everything it started", posix, async () => {
	const t = Date.now();
	const r = await run("sh", ["-c", HOLDER], { cwd: ".", timeoutMs: 500 });
	assert.equal(r.timedOut, true);
	assert.ok(Date.now() - t < 5000, "returned without waiting for the child");
	await delay(100);
	assert.equal(alive(childPid(r.output)), false);
});

test("children: kill ends what the command left running once it exits", posix, async () => {
	const t = Date.now();
	const r = await run("sh", ["-c", "sleep 60 & echo child=$!"], { cwd: ".", timeoutMs: 30_000, children: "kill" });
	assert.equal(r.timedOut, false);
	assert.equal(r.code, 0);
	assert.ok(Date.now() - t < 5000, "returned without waiting for the child");
	await delay(100);
	assert.equal(alive(childPid(r.output)), false);
});

test("by default the output of children that finish later is kept", async () => {
	// A child that inherits the output and writes after its parent has gone.
	const late = "setTimeout(() => console.log('late'), 300)";
	const parent = `require("node:child_process").spawn(process.execPath, ["-e", ${JSON.stringify(late)}], { stdio: "inherit", detached: true }).unref(); console.log("early")`;
	const r = await run(process.execPath, ["-e", parent], { cwd: ".", timeoutMs: 10_000 });
	assert.match(r.output, /early/);
	assert.match(r.output, /late/);
});

test("output is seen as it comes", async () => {
	const seen: string[] = [];
	await run(process.execPath, ["-e", "console.log('one'); console.log('two')"], { cwd: ".", timeoutMs: 10_000, onOutput: (t) => seen.push(t) });
	assert.match(seen.join(""), /one\ntwo/);
});

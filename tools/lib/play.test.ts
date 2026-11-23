import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import type { Game as ApiGame } from "./debug-api.ts";
import { apiForLog, flatDistance, float, ONE_SHOTS, godotValue, roundsFired, SLOW_WITHIN_M, steer, WALK_SPEED, walkTimeoutMs, WEAPON_SLOTS, makeExpect, nodePath, parsePlayArgs, parseState, parseVec3, PlaytestFailure, PORT_BAND, preferredPort, Recorder, scanPlayLog, vec2, vec3, yawPitchTo } from "./play.ts";
import { finalStatus, reportMarkdown, reviewMarkdown, summarisePerf, type Report } from "./play-report.ts";

test("arguments: a scenario and options", () => {
	assert.deepEqual(parsePlayArgs(["partner-marker", "--keep", "--port", "7900", "--headless", "--timeout", "90"]), { scenario: "partner-marker", keep: true, headless: true, port: 7900, timeoutSeconds: 90, list: false });
	assert.equal(parsePlayArgs(["--list"]).list, true);
	assert.throws(() => parsePlayArgs([]), /name a scenario/);
	assert.throws(() => parsePlayArgs(["a", "b"]), /one scenario/);
	assert.throws(() => parsePlayArgs(["a", "--port", "x"]), /positive whole number/);
	assert.throws(() => parsePlayArgs(["a", "--nope"]), /unknown option/);
	assert.throws(() => parsePlayArgs(["../escape"]), /lower-case words/);
});

test("the first port tried stays in the band, away from the gate's", () => {
	assert.equal(preferredPort(0), PORT_BAND.from);
	assert.equal(preferredPort(0.9999999), PORT_BAND.from + PORT_BAND.span - 1);
	assert.equal(preferredPort(2), PORT_BAND.from + PORT_BAND.span - 1);
	assert.ok(PORT_BAND.from > 7796);
});

test("values are written the way Godot's str_to_var reads them", () => {
	assert.equal(godotValue(2), "2");
	assert.equal(godotValue(2.5), "2.5");
	assert.equal(godotValue(float(23)), "23.0");
	assert.equal(godotValue(true), "true");
	assert.equal(godotValue(null), "null");
	assert.equal(godotValue('say "hi"\n'), '"say \\"hi\\"\\n"');
	assert.equal(godotValue(vec3([1, -2.5, 0])), "Vector3(1.0, -2.5, 0.0)");
	assert.equal(godotValue(vec2([0, 1])), "Vector2(0.0, 1.0)");
	assert.equal(godotValue(nodePath("/root/Boot")), 'NodePath("/root/Boot")');
	assert.throws(() => godotValue(Number.NaN), /cannot send/);
});

test("vectors read from either form the debug API gives", () => {
	assert.deepEqual(parseVec3("Vector3(-56, 10.500455, -810)"), [-56, 10.500455, -810]);
	assert.deepEqual(parseVec3([1, 2, 3]), [1, 2, 3]);
	assert.equal(parseVec3("Vector2(1, 2)"), undefined);
	assert.equal(parseVec3([1, "2", 3]), undefined);
});

test("looking from one point at another: forward is -Z, up is positive pitch", () => {
	const ahead = yawPitchTo([0, 0, 0], [0, 0, -10]);
	assert.ok(Math.abs(ahead.yaw) < 1e-9 && Math.abs(ahead.pitch) < 1e-9);
	assert.ok(Math.abs(yawPitchTo([0, 0, 0], [-10, 0, 0]).yaw - Math.PI / 2) < 1e-9);
	assert.ok(Math.abs(yawPitchTo([0, 0, 0], [0, 10, -10]).pitch - Math.PI / 4) < 1e-9);
});

test("a process's debug API is found by the log it writes", () => {
	const games: ApiGame[] = [
		{ pid: 1, role: "server", port: 1, token: "a", log: "/x/logs/server.log", file: "" },
		{ pid: 2, role: "client", port: 2, token: "b", log: "/x/logs/Ana.log", file: "" },
		{ pid: 3, role: "client", port: 3, token: "c", log: "", file: "" },
	];
	assert.equal(apiForLog(games, "/x/logs/Ana.log")?.pid, 2);
	assert.equal(apiForLog(games, "/y/logs/Ana.log"), undefined);
	assert.equal(apiForLog(games, ""), undefined);
});

test("game state is read defensively", () => {
	const s = parseState({ role: "client", mode: "client", connected: true, peer_id: 7, modules: ["a", 3], players: [{ path: "/p", name: "7", peer_id: 7, player_name: "Ana", local: true, at: [1, 2, 3] }, { position: "Vector3(4, 5, 6)" }] });
	assert.equal(s.peerId, 7);
	assert.deepEqual(s.modules, ["a"]);
	assert.equal(s.players[0]?.playerName, "Ana");
	assert.equal(s.players[0]?.local, true);
	assert.deepEqual(s.players[1]?.at, [4, 5, 6]);
	assert.deepEqual(parseState(null).players, []);
});

test("logs: errors fail unless allowed, warnings are counted", () => {
	const log = ["ok", "ERROR: boom", "SCRIPT ERROR: bad", "WARNING: [WARN] net: hm", "ERROR: Pages in use exist at exit in PagedAllocator"].join("\n");
	const scan = scanPlayLog(log, [/bad/]);
	assert.deepEqual(scan.errors, ["ERROR: boom"]);
	assert.equal(scan.allowed, 1);
	assert.equal(scan.warningCount, 1);
});

test("expectations record steps and throw with what was seen", async () => {
	const rec = new Recorder();
	rec.log = () => {};
	const expect = makeExpect(rec);
	expect(3, "apples").toBe(3);
	assert.throws(() => expect([1, 2], "list").toContain(5), (e: unknown) => e instanceof PlaytestFailure && /expected list to contain 5; got \[1,2\]/.test(e.message));
	let calls = 0;
	const got = await expect.poll(() => ++calls, { what: "counter", interval: 1 }).toBeGreaterThan(2);
	assert.equal(got, 3);
	await assert.rejects(expect.poll(() => 0, { what: "never", timeout: 30, interval: 5 }).toBe(1), /expected never to be 1 within 0.03 s; last value 0/);
	await assert.rejects(
		expect.poll(
			() => {
				throw new Error("not up");
			},
			{ what: "api", timeout: 20, interval: 5 },
		).toBeTruthy(),
		/last try threw: not up/,
	);
	assert.deepEqual(
		rec.steps.map((s) => [s.kind, s.ok]),
		[
			["assert", true],
			["assert", false],
			["wait", true],
			["wait", false],
			["wait", false],
		],
	);
});

function report(over: Partial<Report> = {}): Report {
	return {
		scenario: "s",
		title: "T",
		started: "2026-11-22T00:00:00.000Z",
		durationMs: 1500,
		status: "passed",
		headless: false,
		port: 7850,
		steps: [{ at: 100, kind: "assert", title: "x | y", ok: true }],
		shots: [{ name: "a", client: "Ana", file: "shots/01-Ana-a.png", expect: "a blue marker", at: 200, checks: [{ title: "blue", ok: true, detail: "9 px" }] }],
		logs: [{ process: "server", file: "logs/server.log", errors: [], allowed: 0, warnings: [], warningCount: 0 }],
		perf: [summarisePerf("Ana", [{ fps: 60, p95: 20, max: 30 }, { fps: 40, p95: 25, max: 50 }])],
		...over,
	};
}

test("a run fails on any failed step, image check, error or log error line", () => {
	assert.equal(finalStatus(report(), "passed"), "passed");
	assert.equal(finalStatus(report({ error: "x" }), "passed"), "failed");
	assert.equal(finalStatus(report({ steps: [{ at: 0, kind: "wait", title: "w", ok: false }] }), "passed"), "failed");
	assert.equal(finalStatus(report({ logs: [{ process: "Ana", file: "", errors: ["ERROR: x"], allowed: 0, warnings: [], warningCount: 0 }] }), "passed"), "failed");
	const badShot = report().shots.map((s) => ({ ...s, checks: [{ title: "c", ok: false, detail: "" }] }));
	assert.equal(finalStatus(report({ shots: badShot }), "passed"), "failed");
	assert.equal(finalStatus(report({ error: "off" }), "skipped"), "skipped");
});

test("the report has steps, shots, logs and perf; the review only shots and expectations", () => {
	const md = reportMarkdown(report());
	assert.match(md, /\*\*PASSED\*\*/);
	assert.match(md, /x \\\| y/);
	assert.match(md, /shots\/01-Ana-a.png/);
	assert.match(md, /\| Ana \| 2 \| 40 \| 25.0 ms \| 50.0 ms \|/);
	const review = reviewMarkdown(report(), "/runs/1");
	assert.match(review, /\/runs\/1\/shots\/01-Ana-a.png\n {2}Expectation: a blue marker/);
	assert.doesNotMatch(review, /x \| y|9 px|server/);
	assert.match(reviewMarkdown(report({ shots: [] }), "/r"), /no screenshots/);
});

// A module's file, or undefined once that module is deleted (its sync test then skips).
function moduleFile(...path: string[]): string | undefined {
	const file = join(import.meta.dirname, "..", "..", "modules", ...path);
	return existsSync(file) ? readFileSync(file, "utf8") : undefined;
}

test("the one-shot actions match PlayerIntent's", (t) => {
	const gd = moduleFile("player", "scripts", "player_intent.gd");
	if (gd === undefined) return t.skip("player module removed");
	const line = /const ONE_SHOTS := \[(.*)\]/.exec(gd)?.[1] ?? "";
	assert.deepEqual([...line.matchAll(/&"(\w+)"/g)].map((m) => m[1]), [...ONE_SHOTS]);
});

test("walking: face the target, ease off near it, stop within reach", () => {
	const far = steer([0, 5, 0], [0, 0, -10], 1);
	assert.ok(Math.abs(far.yaw) < 1e-9, "forward is -Z whatever the height");
	assert.equal(far.forward, 1);
	assert.equal(far.arrived, false);
	assert.equal(far.distance, 10);
	const near = steer([0, 0, 0], [SLOW_WITHIN_M / 2, 0, 0], 0.5);
	assert.ok(near.forward > 0 && near.forward < 1);
	assert.ok(Math.abs(near.yaw + Math.PI / 2) < 1e-9, "+X is a quarter turn right");
	const there = steer([0, 0, 0], [0.5, 9, 0], 1);
	assert.deepEqual([there.arrived, there.forward], [true, 0]);
	assert.equal(flatDistance([0, 0, 0], [3, 100, 4]), 5);
});

test("a walk may take three times walking pace, never under 10 s", () => {
	assert.equal(walkTimeoutMs(1), 10_000);
	assert.equal(walkTimeoutMs(45, 4.5), 30_000);
});

test("rounds fired between magazine readings never go negative", () => {
	assert.equal(roundsFired(30, 27), 3);
	assert.equal(roundsFired(2, 30), 0, "a reload in between");
	assert.equal(roundsFired(-1, 5), 0, "not heard from the server yet");
});

test("the weapon slots match the weapons module's", (t) => {
	const gd = moduleFile("weapons", "weapons_module.gd");
	if (gd === undefined) return t.skip("weapons module removed");
	const line = /const WEAPON_SLOTS: Array\[String\] = \[(.*)\]/.exec(gd)?.[1] ?? "";
	assert.deepEqual([...line.matchAll(/"(\w+)"/g)].map((m) => m[1]), [...WEAPON_SLOTS]);
});

test("the walking pace matches player.json", (t) => {
	const json = moduleFile("player", "data", "player.json");
	if (json === undefined) return t.skip("player module removed");
	const data: unknown = JSON.parse(json);
	assert.equal(typeof data === "object" && data !== null ? Reflect.get(data, "walk_speed") : undefined, WALK_SPEED);
});

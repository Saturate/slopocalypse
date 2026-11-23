import { test } from "node:test";
import assert from "node:assert/strict";
import { serverArgs } from "./server.ts";

test("the port defaults and can be set", () => {
	assert.deepEqual(serverArgs([]), { port: "7777", game: ["--server=7777"] });
	assert.deepEqual(serverArgs(["--port", "7790"]), { port: "7790", game: ["--server=7790"] });
	assert.equal(serverArgs(["--port=7790"]).port, "7790");
});

test("everything after -- reaches the game", () => {
	assert.deepEqual(serverArgs(["--port", "7790", "--", "--web", "--no-save"]).game, ["--server=7790", "--web", "--no-save"]);
	// A --port after -- is the game's, not ours.
	assert.equal(serverArgs(["--", "--port", "1"]).port, "7777");
});

test("a bad port is refused", () => {
	assert.throws(() => serverArgs(["--port"]));
	assert.throws(() => serverArgs(["--port", "--web"]));
	assert.throws(() => serverArgs(["--port", "70000"]));
});

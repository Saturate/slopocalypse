import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import { godotUserDir, parseApiFile, pickTarget, type Game } from "./debug-api.ts";

test("the user folder follows Godot's per-OS location", () => {
	assert.equal(godotUserDir("win32", { APPDATA: "C:\Users\a\AppData\Roaming" }, "C:\Users\a"), join("C:\Users\a\AppData\Roaming", "Godot", "app_userdata", "Slopocalypse"));
	assert.equal(godotUserDir("linux", {}, "/home/a"), join("/home/a", ".local", "share", "godot", "app_userdata", "Slopocalypse"));
	assert.equal(godotUserDir("linux", { XDG_DATA_HOME: "/data/.local/share" }, "/data"), join("/data/.local/share", "godot", "app_userdata", "Slopocalypse"));
	assert.equal(godotUserDir("darwin", {}, "/Users/a"), join("/Users/a", "Library", "Application Support", "Godot", "app_userdata", "Slopocalypse"));
});

test("an api file needs a pid, port and token", () => {
	assert.deepEqual(parseApiFile('{"pid": 12, "role": "server", "port": 5000, "token": "ab", "log": "x.log"}', "f"), { pid: 12, role: "server", port: 5000, token: "ab", log: "x.log", file: "f" });
	assert.equal(parseApiFile('{"pid": 12}', "f"), undefined);
	assert.equal(parseApiFile("not json", "f"), undefined);
});

const games: Game[] = [
	{ pid: 10, role: "server", port: 1, token: "a", log: "", file: "" },
	{ pid: 20, role: "client", port: 2, token: "b", log: "", file: "" },
];

test("the client is the default target; a pid or role picks one", () => {
	assert.equal(pickTarget(games, undefined)?.pid, 20);
	assert.equal(pickTarget(games, "server")?.pid, 10);
	assert.equal(pickTarget(games, 10)?.pid, 10);
	assert.equal(pickTarget(games, "10")?.pid, 10);
	assert.equal(pickTarget(games, "99"), undefined);
	assert.equal(pickTarget([games[0]!], undefined)?.pid, 10);
});

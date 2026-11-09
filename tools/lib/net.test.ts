import { test } from "node:test";
import assert from "node:assert/strict";
import { parseReport, parseSoloServer } from "./net.ts";

test("reads the solo server line, Windows path and CRLF included", () => {
	const out = "[INFO] net: solo server pid=1234 port=7800 log=C:/Users/me/AppData/Roaming/Godot/app_userdata/Slopocalypse/logs/solo-server.log\r\n[INFO] boot: loaded";
	assert.deepEqual(parseSoloServer(out), { pid: 1234, port: 7800, log: "C:/Users/me/AppData/Roaming/Godot/app_userdata/Slopocalypse/logs/solo-server.log" });
});

test("no solo server line means undefined", () => {
	assert.equal(parseSoloServer("[INFO] net: solo session\n"), undefined);
});

test("reads a net report", () => {
	const rep = parseReport("NET-REPORT mode=SOLO peer=55 peers=1 players=1 local_players=1 moved=12.5 shots=4 driven=7.0 ammo=17");
	assert.deepEqual(rep, { mode: "SOLO", peer: 55, peers: 1, players: 1, localPlayers: 1, moved: 12.5, shots: 4, driven: 7, ammo: 17 });
});

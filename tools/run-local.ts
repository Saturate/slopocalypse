// Starts a dedicated server and two windowed clients on this machine, to see multiplayer
// end to end.   node tools/run-local.ts [--port 7777]
import { resolve } from "node:path";
import { argv } from "node:process";
import { spawn } from "node:child_process";
import { localGodot } from "./lib/godot.ts";

const root = resolve(import.meta.dirname, "..");
const godot = localGodot(root);
const i = argv.indexOf("--port");
const port = i >= 0 ? argv[i + 1] : "7777";
spawn(godot, ["--headless", "--path", root, "--", `--server=${port}`], { cwd: root, stdio: "inherit" });
// Give the server a moment to load the world before the clients join.
setTimeout(() => {
	// Two windows on one machine share a profile, so each gets its own name to save under.
	for (const [pos, name] of [["40,60", "Local1"], ["1000,60", "Local2"]] as const) {
		spawn(godot, ["--path", root, "--resolution", "900x540", "--position", pos, "--", `--connect=127.0.0.1:${port}`, `--name=${name}`], { cwd: root, stdio: "inherit" });
	}
}, 4000);

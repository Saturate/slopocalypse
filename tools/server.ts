// Runs a dedicated server: headless, no window, no local player.
//   node tools/server.ts [--port 7777] [-- <game arguments, e.g. --web --no-save>]
import { resolve } from "node:path";
import { argv, exit } from "node:process";
import { spawn } from "node:child_process";
import { localGodot } from "./lib/godot.ts";
import { serverArgs } from "./lib/server.ts";

const root = resolve(import.meta.dirname, "..");
let parsed: { port: string; game: string[] };
try {
	parsed = serverArgs(argv.slice(2));
} catch (e) {
	console.error(e instanceof Error ? e.message : String(e));
	exit(1);
}
const { port, game } = parsed;
console.log(`Slopocalypse server on UDP port ${port} (Ctrl+C to stop)`);
spawn(localGodot(root), ["--headless", "--path", root, "--", ...game], { cwd: root, stdio: "inherit" });

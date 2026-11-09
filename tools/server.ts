// Runs a dedicated server: headless, no window, no local player.
//   node tools/server.ts [--port 7777]
import { resolve } from "node:path";
import { argv } from "node:process";
import { spawn } from "node:child_process";
import { localGodot } from "./lib/godot.ts";

const root = resolve(import.meta.dirname, "..");
const i = argv.indexOf("--port");
const port = i >= 0 ? argv[i + 1] : "7777";
console.log(`Slopocalypse server on UDP port ${port} (Ctrl+C to stop)`);
spawn(localGodot(root), ["--headless", "--path", root, "--", `--server=${port}`], { cwd: root, stdio: "inherit" });

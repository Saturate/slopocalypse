// Renders a capture setup to a PNG so Claude (or a reviewer) can look at the game.
//   node tools/capture.ts --setup res://modules/player/capture/walk.gd --out screenshots/walk.png [--frames 90] [--sheet 6]
// Opens a real window: rendering is needed, headless Godot draws nothing.
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { argv, exit } from "node:process";
import { GODOT_NOISE } from "./lib/gate.ts";
import { localGodot } from "./lib/godot.ts";
import { scanLog } from "./lib/log-scan.ts";
import { run } from "./lib/proc.ts";

const root = resolve(import.meta.dirname, "..");

function arg(name: string, fallback?: string): string {
	const i = argv.indexOf(`--${name}`);
	const value = i >= 0 ? argv[i + 1] : fallback;
	if (value === undefined) {
		console.error(`missing --${name}`);
		exit(1);
	}
	return value;
}

const setup = arg("setup");
const outArg = arg("out");
const out = isAbsolute(outArg) ? outArg : join(root, outArg);
mkdirSync(dirname(out), { recursive: true });
// Keep Godot's importer away from captured PNGs.
const shots = join(root, "screenshots");
if (!existsSync(join(shots, ".gdignore"))) {
	mkdirSync(shots, { recursive: true });
	writeFileSync(join(shots, ".gdignore"), "");
}

const r = await run(
	localGodot(root),
	[
		"--path", root,
		"--resolution", "1280x720",
		"--fixed-fps", "30",
		"-s", "res://tools/gd/capture.gd",
		"--",
		"--setup", setup,
		"--out", out,
		"--frames", arg("frames", "60"),
		"--sheet", arg("sheet", "1"),
	],
	{ cwd: root, timeoutMs: 120_000 },
);
const problems = scanLog(r.output, GODOT_NOISE);
if (r.code !== 0 || problems.length > 0 || !existsSync(out)) {
	console.error(`capture failed (exit ${r.code})`);
	for (const p of problems) console.error("  " + p);
	exit(1);
}
console.log(out);

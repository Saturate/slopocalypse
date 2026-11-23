// Shows a capture as colour-blind players see it (#447): writes <out>-normal.png, -protan.png,
// -deutan.png and -tritan.png. --crop cuts out part of the image first and --scale enlarges it
// with hard pixel edges, so bands a few pixels wide can be judged.
//   node tools/colour-vision.ts --in screenshots/armbands.png --out screenshots/armbands [--crop x,y,w,h] [--scale 5]
import { resolve } from "node:path";
import { argv, exit } from "node:process";
import { localGodot } from "./lib/godot.ts";
import { run } from "./lib/proc.ts";

const root = resolve(import.meta.dirname, "..");

function arg(name: string): string | undefined {
	const i = argv.indexOf(`--${name}`);
	return i >= 0 ? argv[i + 1] : undefined;
}

const input = arg("in");
const out = arg("out");
if (input === undefined || out === undefined) {
	console.error("usage: node tools/colour-vision.ts --in <png> --out <path without .png> [--crop x,y,w,h] [--scale N]");
	exit(1);
}
const extra: string[] = [];
for (const name of ["crop", "scale"]) {
	const value = arg(name);
	if (value !== undefined) extra.push(`--${name}`, value);
}
const r = await run(
	localGodot(root),
	["--headless", "--path", root, "-s", "res://tools/gd/colour_vision.gd", "--", "--in", resolve(input), "--out", resolve(out), ...extra],
	{ cwd: root, timeoutMs: 300_000 },
);
process.stdout.write(r.output);
exit(r.code === 0 && !r.timedOut ? 0 : 1);

// Renders a map recipe's land top-down to a PNG for review (#427):
//   node tools/map-preview.ts [--map=grassland] [--seed=1] [--pixels=512] [--out=build/maps/grassland-1.png]
import { mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { localGodot } from "./lib/godot.ts";
import { parsePreviewArgs, recipePath } from "./lib/map-preview.ts";
import { run } from "./lib/proc.ts";

const root = resolve(import.meta.dirname, "..");
const args = parsePreviewArgs(process.argv.slice(2));
const out = resolve(root, args.out);
mkdirSync(dirname(out), { recursive: true });
const r = await run(localGodot(root), ["--headless", "--path", root, "-s", "res://tools/gd/map_preview.gd", "--", recipePath(args.map), String(args.seed), out, String(args.pixels)], { cwd: root, timeoutMs: 300_000 });
process.stdout.write(r.output);
process.exit(r.code === 0 && !r.timedOut ? 0 : 1);

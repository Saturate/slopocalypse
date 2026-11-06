// Regenerates every builder-made scene. Run after changing a builder; commit the .tscn output.
import { resolve } from "node:path";
import { exit } from "node:process";
import { localGodot } from "./lib/godot.ts";
import { buildScenes } from "./lib/scenes.ts";

const root = resolve(import.meta.dirname, "..");
const r = await buildScenes(localGodot(root), root);
console.log(r.detail);
for (const c of r.changed) console.log(`  changed: ${c}`);
exit(r.ok ? 0 : 1);

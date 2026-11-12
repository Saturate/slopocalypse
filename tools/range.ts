// Opens the test range: a solo game that rides straight to a row of buildings, one per
// material, to break things and see how each takes it (no guards, no clock, nothing saved).
//   node tools/range.ts [--bot]
// --bot lets the range bot work through the row on its own (what the range-destroy bench runs).
import { resolve } from "node:path";
import { spawn } from "node:child_process";
import { argv } from "node:process";
import { localGodot } from "./lib/godot.ts";

const root = resolve(import.meta.dirname, "..");
const extra = argv.includes("--bot") ? ["--bot=range"] : [];
spawn(localGodot(root), ["--path", root, "--", "--solo", "--range", "--no-save", ...extra], { cwd: root, stdio: "inherit" });

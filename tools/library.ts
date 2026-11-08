// Opens the voxel asset library: every model the kit makes, with live parameters and the
// pixel filter.   node tools/library.ts
import { resolve } from "node:path";
import { spawn } from "node:child_process";
import { localGodot } from "./lib/godot.ts";

const root = resolve(import.meta.dirname, "..");
spawn(localGodot(root), ["--path", root, "--", "--library"], { cwd: root, stdio: "inherit" });

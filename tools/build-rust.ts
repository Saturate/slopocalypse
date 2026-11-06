// Builds every module's gdext binding crate and copies the library into modules/<id>/bin/,
// where that module's .gdextension expects it. `--release` for exports.
import { resolve } from "node:path";
import { argv, exit } from "node:process";
import { buildRust } from "./lib/rust.ts";

const root = resolve(import.meta.dirname, "..");
const r = await buildRust(root, argv.includes("--release"));
console.log(r.detail);
exit(r.ok ? 0 : 1);

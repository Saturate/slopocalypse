import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { binDir, findBindingCrates, libraryFile } from "./rust.ts";

test("library file name follows each OS convention", () => {
	assert.equal(libraryFile("example_gd", "win32"), "example_gd.dll");
	assert.equal(libraryFile("example_gd", "linux"), "libexample_gd.so");
	assert.equal(libraryFile("example_gd", "darwin"), "libexample_gd.dylib");
});

test("bin dir matches the paths in .gdextension files", () => {
	assert.equal(binDir("modules/example", "win32", "debug"), join("modules/example", "bin", "windows", "debug"));
	assert.equal(binDir("modules/example", "darwin", "release"), join("modules/example", "bin", "macos", "release"));
});

test("finds cdylib crates under modules/*/rust/* and skips pure crates", () => {
	const root = mkdtempSync(join(tmpdir(), "outpost-rust-"));
	const crate = (mod: string, dir: string, toml: string): void => {
		mkdirSync(join(root, "modules", mod, "rust", dir), { recursive: true });
		writeFileSync(join(root, "modules", mod, "rust", dir, "Cargo.toml"), toml);
	};
	crate("car", "core", '[package]\nname = "car_core"\n');
	crate("car", "gd", '[package]\nname = "car_gd"\n\n[lib]\ncrate-type = ["cdylib"]\n');
	mkdirSync(join(root, "modules", "plain"), { recursive: true });

	const found = findBindingCrates(root);
	assert.equal(found.length, 1);
	assert.equal(found[0]?.name, "car_gd");
	assert.equal(found[0]?.moduleDir, join(root, "modules", "car"));
});

test("no modules folder means no crates", () => {
	assert.deepEqual(findBindingCrates(mkdtempSync(join(tmpdir(), "outpost-empty-"))), []);
});

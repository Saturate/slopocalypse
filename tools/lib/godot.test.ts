import { test } from "node:test";
import assert from "node:assert/strict";
import { assetFor, executableIn, GODOT_VERSION } from "./godot.ts";

test("pinned version is 4.7.2-stable", () => {
	assert.equal(GODOT_VERSION, "4.7.2-stable");
});

test("picks the official asset for each supported platform", () => {
	assert.equal(assetFor("win32", "x64"), "Godot_v4.7.2-stable_win64.exe.zip");
	assert.equal(assetFor("win32", "arm64"), "Godot_v4.7.2-stable_windows_arm64.exe.zip");
	assert.equal(assetFor("linux", "x64"), "Godot_v4.7.2-stable_linux.x86_64.zip");
	assert.equal(assetFor("linux", "arm64"), "Godot_v4.7.2-stable_linux.arm64.zip");
	assert.equal(assetFor("darwin", "x64"), "Godot_v4.7.2-stable_macos.universal.zip");
	assert.equal(assetFor("darwin", "arm64"), "Godot_v4.7.2-stable_macos.universal.zip");
});

test("rejects platforms without an official build", () => {
	assert.throws(() => assetFor("freebsd", "x64"), /no official Godot build/);
	assert.throws(() => assetFor("linux", "ia32"), /no official Godot build/);
});

test("console executable on Windows so headless output reaches the terminal", () => {
	assert.equal(
		executableIn("tools/godot", "win32", "x64"),
		"tools/godot/Godot_v4.7.2-stable_win64_console.exe",
	);
	assert.equal(
		executableIn("tools/godot", "linux", "arm64"),
		"tools/godot/Godot_v4.7.2-stable_linux.arm64",
	);
	assert.equal(
		executableIn("tools/godot", "darwin", "arm64"),
		"tools/godot/Godot.app/Contents/MacOS/Godot",
	);
});

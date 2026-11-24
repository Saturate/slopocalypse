import { test } from "node:test";
import assert from "node:assert/strict";
import { assetFor, executableIn, GODOT_BUNDLE_ID, GODOT_VERSION, quietWindow } from "./godot.ts";

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

test("a tool's window on macOS keeps drawing on top without taking focus", () => {
	const w = quietWindow("darwin", { __CFBundleIdentifier: "com.example.terminal", HOME: "/h" });
	assert.deepEqual(w.args, ["--audio-driver", "Dummy", "--always-on-top"]);
	assert.equal(w.env.__CFBundleIdentifier, GODOT_BUNDLE_ID);
	assert.equal(w.env.HOME, "/h");
});

test("other systems keep the window as it is, without sound", () => {
	const env = { HOME: "/h" };
	assert.deepEqual(quietWindow("win32", env), { args: ["--audio-driver", "Dummy"], env });
	assert.deepEqual(quietWindow("linux", env), { args: ["--audio-driver", "Dummy"], env });
});

test("SLOP_SOUND=1 keeps the sound", () => {
	assert.deepEqual(quietWindow("linux", { SLOP_SOUND: "1" }).args, []);
	assert.deepEqual(quietWindow("darwin", { SLOP_SOUND: "1" }).args, ["--always-on-top"]);
});

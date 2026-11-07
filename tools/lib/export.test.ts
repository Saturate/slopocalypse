import { test } from "node:test";
import { join } from "node:path";
import assert from "node:assert/strict";
import { dataFiles, presetFor, shippedServers, presetsFile, templatesDir } from "./export.ts";

test("windows preset embeds the pack, keeps data files and drops dev-only folders", () => {
	const p = presetFor("windows", "build/windows/Outpost.exe");
	assert.equal(p.platform, "Windows Desktop");
	const text = presetsFile([p]);
	assert.match(text, /\[preset\.0\]/);
	assert.match(text, /platform="Windows Desktop"/);
	assert.match(text, /export_path="build\/windows\/Outpost.exe"/);
	assert.match(text, /include_filter="[^"]*\*\.json/);
	for (const dev of ["tests/*", "tools/*", "addons/gdUnit4/*", "modules/*/tests/*", "modules/*/builders/*", "modules/*/capture/*", "modules/*/rust/*"]) {
		assert.ok(text.includes(dev), `exclude filter misses ${dev}`);
	}
	assert.match(text, /\[preset\.0\.options\]/);
	assert.match(text, /binary_format\/embed_pck=true/);
	// A console wrapper lets the host run a visible server window.
	assert.match(text, /debug\/export_console_wrapper=2/);
});

test("linux and macos presets name their platforms", () => {
	assert.equal(presetFor("linux", "x").platform, "Linux");
	assert.equal(presetFor("macos", "x").platform, "macOS");
});

test("templates live in the self-contained editor data, per engine version", () => {
	assert.equal(templatesDir("/p/tools/godot", "4.7.2-stable").replaceAll("\\", "/"), "/p/tools/godot/editor_data/export_templates/4.7.2.stable");
});

test("shipped servers list every --connect address for the menu", () => {
	const parsed: unknown = JSON.parse(shippedServers("100.64.1.2:7777, game.example.net"));
	assert.deepEqual(parsed, { servers: ["100.64.1.2:7777", "game.example.net"] });
});

test("the tunable data files are the root and module data folders", () => {
	const files = dataFiles(join(import.meta.dirname, "..", ".."));
	assert.ok(files.includes("data/features.json"), files.join(", "));
	assert.ok(files.includes("modules/enemies/data/enemies.json"), files.join(", "));
	assert.ok(files.every((f) => f.endsWith(".json") && !f.includes("\\")));
});

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "..", "..");

// The project theme is loaded while the engine starts, before a fresh checkout has its list
// of class names, so its scripts must reach other scripts by preload. A class name there
// parses locally (the cache exists) and breaks every fresh import: CI and release builds.
const STARTUP = ["core/ui/ui_theme.gd", "core/ui/steel_plate.gd", "core/ui/ui_palette.gd"];
const CLASS_NAMES = ["UiPalette", "SteelPlate", "UiTheme", "UiText", "UiStack", "UiLayers"];

test("the theme reads its fonts from the .ttf, which exists before the first import", () => {
	const theme = readFileSync(join(root, "core/ui/ui_theme.gd"), "utf8");
	assert.match(theme, /FileAccess\.get_file_as_bytes\(path\)/);
	assert.ok(!/load\((HEADING|BODY|NUMBER)_FONT\)/.test(theme), "a font loaded as a resource fails before import");
});

test("scripts loaded at engine start name no global classes", () => {
	const project = readFileSync(join(root, "project.godot"), "utf8");
	assert.match(project, /theme\/custom="res:\/\/core\/ui\/ui_theme\.tres"/);
	for (const file of STARTUP) {
		const code = readFileSync(join(root, file), "utf8")
			.split("\n")
			.filter((line) => !line.trimStart().startsWith("#") && !line.startsWith("class_name"))
			.join("\n");
		for (const name of CLASS_NAMES) {
			assert.ok(!new RegExp(`\\b${name}\\b`).test(code), `${file} names ${name}; preload it instead`);
		}
	}
});
